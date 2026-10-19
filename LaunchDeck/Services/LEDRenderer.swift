// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import Foundation

@MainActor
final class LEDRenderer {
    private let model: () -> DeviceModel
    private let send: ([UInt8]) -> Void
    private let clock: () -> TimeInterval
    private let automaticallyAnimate: Bool
    var onFrame: (([Int: PadColor]) -> Void)?
    var isAnimating: Bool { requiresAnimation }
    private var activeLayout: ResolvedLayout?
    private var lastSent: [Int: PadColor] = [:]
    private var lastFrame: [Int: PadColor] = [:]
    private var sentModel: DeviceModel?
    private var paused = false
    private var stopped = false
    private var generation = 0
    private var animationTask: Task<Void, Never>?
    private var lastAnimationFrameTime: TimeInterval?
    private var presses: [LightingPress] = []
    private var statuses: [Int: LightingStatus] = [:]
    private var applicationStates: [Int: ApplicationLightState] = [:]
    private var audioLevel: Double = 0
    private var pendingFrame = false
    private struct Flash { let color: PadColor; let expiresAt: TimeInterval }
    private var flashes: [Int: Flash] = [:]

    convenience init(midi: MIDIService) {
        self.init(model: { midi.connectedModel ?? .miniMK3 }, send: { midi.sendSysEx($0) })
    }
    init(model: @escaping () -> DeviceModel, send: @escaping ([UInt8]) -> Void,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, automaticallyAnimate: Bool = true) {
        self.model = model; self.send = send; self.clock = clock; self.automaticallyAnimate = automaticallyAnimate
    }
    deinit { animationTask?.cancel() }

    func render(_ layout: ResolvedLayout, paused: Bool) {
        cancelAnimation()
        activeLayout = layout; self.paused = paused; stopped = false
        publish(desiredColors(at: now))
        scheduleIfNeeded()
    }
    func repaint() {
        // Unknown hardware state requires every black entry, too. Old page feedback cannot survive reconnects.
        cancelAnimation()
        lastSent.removeAll()
        guard !stopped else { return }
        publish(desiredColors(at: now), forceCallback: true)
        scheduleIfNeeded()
    }
    func press(index: Int, effect: PressEffect? = nil, color: PadColor? = nil) {
        guard accepts(index), let layout = activeLayout else { return }
        let effect = effect ?? layout.binding(at: index)?.pressEffect ?? layout.lighting.pressEffect
        guard effect != .none else { return }
        presses.append(LightingPress(index: index, effect: effect, color: color ?? layout.lighting.accentColor, startedAt: now))
        if presses.count > LightingPress.maximumCount { presses.removeFirst(presses.count - LightingPress.maximumCount) }
        pendingFrame = true
        tick()
    }
    func setStatus(index: Int, status: LightingActionStatus?) {
        guard accepts(index), activeLayout?.lighting.showsActionStatus == true else { return }
        statuses[index] = status.map { LightingStatus(status: $0, startedAt: now) }
        pendingFrame = true
        tick()
    }
    func setApplicationStates(_ states: [Int: ApplicationLightState]) {
        guard isActive else { return }
        applicationStates = states.filter { accepts($0.key) }
        pendingFrame = true
        tick()
    }
    func setAudioLevel(_ level: Double) {
        guard isActive else { return }
        audioLevel = level.isFinite ? min(1, max(0, level)) : 0
        pendingFrame = true
        tick()
    }
    func flash(index: Int, color: PadColor, durationNanoseconds: UInt64 = 120_000_000) {
        guard accepts(index), durationNanoseconds > 0 else { return }
        flashes[index] = Flash(color: color, expiresAt: now + Double(durationNanoseconds) / 1_000_000_000)
        pendingFrame = true
        tick()
    }
    func stop(clear: Bool = true) {
        cancelAnimation(); stopped = true
        let black = blackFrame()
        if clear { publish(black) }
        else if lastFrame != black { lastFrame = black; onFrame?(black) }
    }
    func tick() {
        guard !stopped else { return }
        let time = now
        if sentModel != nil && sentModel != model() {
            cancelAnimation()
            publish(blackFrame(), forceCallback: true)
            return
        }
        // Mutations coalesce with the next frame; never send an animation burst above 30 Hz.
        if let last = lastAnimationFrameTime, time >= last, time - last < 1.0 / 30 {
            scheduleIfNeeded()
            return
        }
        lastAnimationFrameTime = time
        prune(at: time)
        pendingFrame = false
        publish(desiredColors(at: time))
        scheduleIfNeeded()
    }

    private var now: TimeInterval { let time = clock(); return time.isFinite ? time : 0 }
    private var isActive: Bool { !stopped && !paused && activeLayout?.model == model() }
    private func accepts(_ index: Int) -> Bool {
        isActive && (0..<model().descriptor.controlCount).contains(index)
            && activeLayout?.pad(at: index)?.isDisabled != true
            && activeLayout?.binding(at: index)?.action != .disabled
    }
    private func blackFrame() -> [Int: PadColor] {
        Dictionary(uniqueKeysWithValues: (0..<model().descriptor.controlCount).map { ($0, .off) })
    }
    private func desiredColors(at time: TimeInterval) -> [Int: PadColor] {
        guard isActive, let layout = activeLayout else { return blackFrame() }
        var frame = LightingComposer.frame(layout: layout, time: time, presses: presses, statuses: statuses, applicationStates: applicationStates, audioLevel: audioLevel)
        for (index, flash) in flashes where accepts(index) && flash.expiresAt > time {
            if layout.lighting.showsActionStatus, statuses[index]?.isActive(at: time) == true { continue }
            // Legacy flash is an explicit color override; retain the page's output brightness.
            let brightness = layout.lighting.brightness.isFinite ? min(1, max(0, layout.lighting.brightness)) : 0
            frame[index] = PadColor(red: Int((Double(min(flash.color.red, 127)) * brightness).rounded()),
                                    green: Int((Double(min(flash.color.green, 127)) * brightness).rounded()),
                                    blue: Int((Double(min(flash.color.blue, 127)) * brightness).rounded()))
        }
        return frame
    }
    private func prune(at time: TimeInterval) {
        let speed = activeLayout?.lighting.speed ?? 1
        presses.removeAll { !$0.isActive(at: time, speed: speed) }
        statuses = statuses.filter { $0.value.isActive(at: time) }
        flashes = flashes.filter { $0.value.expiresAt > time }
    }
    private var requiresAnimation: Bool {
        guard isActive, let layout = activeLayout else { return false }
        switch layout.lighting.ambientEffect {
        case .breathe, .rainbow, .scanner: return true
        case .none, .audioMeter: break
        }
        return pendingFrame || !presses.isEmpty || !statuses.isEmpty || !flashes.isEmpty
    }
    private func cancelAnimation() {
        generation &+= 1
        animationTask?.cancel(); animationTask = nil
        presses.removeAll(); statuses.removeAll(); flashes.removeAll(); applicationStates.removeAll()
        audioLevel = 0; lastAnimationFrameTime = nil; pendingFrame = false
    }
    private func scheduleIfNeeded() {
        guard automaticallyAnimate, animationTask == nil, requiresAnimation else { return }
        let generation = generation
        let device = model()
        // A one-frame task owns only a weak reference while sleeping. Idle/static renderers own no task.
        animationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .nanoseconds(33_333_334)) } catch { return }
            guard let self, self.generation == generation else { return }
            self.animationTask = nil
            guard self.model() == device else { self.cancelAnimation(); self.publish(self.blackFrame()); return }
            self.tick()
        }
    }
    private func publish(_ colors: [Int: PadColor], forceCallback: Bool = false) {
        if lastFrame != colors || forceCallback { lastFrame = colors; onFrame?(colors) }
        let device = model()
        if sentModel != device { lastSent.removeAll(); sentModel = device }
        var changes: [Int: PadColor] = [:]
        for (index, color) in colors where lastSent[index] != color {
            changes[index] = color; lastSent[index] = color
        }
        guard !changes.isEmpty else { return }
        send(DeviceAdapter(model: device).rgbFrame(for: changes))
    }
}
