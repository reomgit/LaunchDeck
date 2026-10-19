import Foundation
import Testing
@testable import LaunchDeckCore

@MainActor
struct LightingTests {
    @Test func disabledControlRejectsLegacyFlash() {
        var messages: [[UInt8]] = []
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { messages.append($0) })
        let pads = (0..<80).map { ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: $0 == 0) }
        renderer.render(ResolvedLayout(revision: 1, pads: pads), paused: false)
        messages.removeAll()
        renderer.flash(index: 0, color: .green)
        #expect(messages.isEmpty)
    }
}

extension LightingTests {
    @Test func staticDefaultsAndArtworkRespectBrightnessAndDisabledPads() throws {
        let decoded = try JSONDecoder().decode(LightingSettings.self, from: Data("{}".utf8))
        #expect(decoded.pressEffect == .glow && decoded.ambientEffect == .none)
        #expect(decoded.brightness == 1 && decoded.speed == 1)
        var settings = LightingSettings()
        settings.brightness = 0.5
        settings.gridArtwork = Array(repeating: PadColor(red: 100, green: 40, blue: 20), count: 64)
        let pads = (0..<80).map { ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: $0 == 1) }
        let layout = ResolvedLayout(revision: 1, pads: pads, lighting: settings)
        let frame = LightingComposer.frame(layout: layout, time: 0)
        #expect(frame[0] == PadColor(red: 50, green: 20, blue: 10))
        #expect(frame[1] == .off)
        #expect(frame[64] == .off)
    }
}

extension LightingTests {
    private func layout(_ settings: LightingSettings = .init(), disabled: Set<Int> = [], revision: Int = 1, model: DeviceModel = .miniMK3, bindingEffect: PressEffect? = nil) -> ResolvedLayout {
        let pads = (0..<model.descriptor.controlCount).map { index in
            ResolvedPad(binding: [0, 64].contains(index) ? PadBinding(index: index, label: "Test", color: PadColor(red: 40, green: 20, blue: 10), action: .shortcut(.copy), pressEffect: bindingEffect) : nil,
                        sourceProfileID: nil, isDisabled: disabled.contains(index))
        }
        return ResolvedLayout(revision: revision, pads: pads, model: model, lighting: settings)
    }

    @Test func rippleExpandsWithoutWrappingAndRestoresBase() {
        let layout = layout()
        let press = LightingPress(index: 0, effect: .ripple, color: .green, startedAt: 0)
        let first = LightingComposer.frame(layout: layout, time: 0, presses: [press])
        #expect(first[0] == .green)
        #expect(first[7] == .off)
        let later = LightingComposer.frame(layout: layout, time: 0.15, presses: [press])
        #expect(later[1] != .off && later[8] != .off)
        #expect(later[7] == .off)
        #expect(LightingComposer.frame(layout: layout, time: 2, presses: [press])[0] == PadColor(red: 40, green: 20, blue: 10))
    }

    @Test func crossAndSparkleHaveDeterministicGridGeometry() {
        let layout = layout()
        let cross = LightingPress(index: 9, effect: .cross, color: .green, startedAt: 0)
        let frame = LightingComposer.frame(layout: layout, time: 0, presses: [cross])
        #expect(frame[1] == .green && frame[8] == .green && frame[17] == .green)
        #expect(frame[10] == .green && frame[18] == .off)
        let sparkle = LightingPress(index: 9, effect: .sparkle, color: .green, startedAt: 0)
        let sparkles = LightingComposer.frame(layout: layout, time: 0.1, presses: [sparkle])
        #expect(sparkles == LightingComposer.frame(layout: layout, time: 0.1, presses: [sparkle]))
        #expect(sparkles[9] != .off)
        #expect(sparkles.values.filter { $0 != .off }.count < 20)
        #expect(sparkles[64] == PadColor(red: 40, green: 20, blue: 10))
    }

    @Test func ambientChangesGridOnlyAndAudioMeterHasLiteralBottomUpLevels() {
        for effect in [AmbientEffect.breathe, .rainbow, .scanner] {
            let layout = layout(LightingSettings(ambientEffect: effect))
            let first = LightingComposer.frame(layout: layout, time: 0)
            let later = LightingComposer.frame(layout: layout, time: 0.5)
            #expect(first != later)
            #expect(later[64] == PadColor(red: 40, green: 20, blue: 10))
        }
        let audio = layout(LightingSettings(ambientEffect: .audioMeter, accentColor: .green))
        let meter = LightingComposer.frame(layout: audio, time: 0, audioLevel: 0.5)
        #expect(meter[0] == .green && meter[31] == .green)
        #expect(meter[32] == .off && meter[63] == .off)
        #expect(LightingComposer.frame(layout: audio, time: 0, audioLevel: .nan)[8] == .off)
    }

    @Test func statusWinsThenRestoresAndAllLayersRespectDisabled() {
        let layout = layout(LightingSettings(ambientEffect: .rainbow), disabled: [1])
        let press = LightingPress(index: 0, effect: .cross, color: .blue, startedAt: 0)
        let status = LightingStatus(status: .failure, startedAt: 0)
        let frame = LightingComposer.frame(layout: layout, time: 0, presses: [press], statuses: [0: status, 1: status], applicationStates: [1: .frontmost])
        #expect(frame[0] == PadColor(red: 127, green: 15, blue: 10))
        #expect(frame[1] == .off)
        #expect(LightingComposer.frame(layout: layout, time: 3, statuses: [0: status]) == LightingComposer.frame(layout: layout, time: 3))
    }

    @Test func passiveApplicationStateOnlyMarksActualLaunchBinding() {
        let binding = PadBinding(index: 0, label: "App", color: .blue, action: .step(.launchApplication(bundleIdentifier: "test")))
        var pads = Array(repeating: ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: false), count: 80)
        pads[0] = ResolvedPad(binding: binding, sourceProfileID: nil, isDisabled: false)
        let layout = ResolvedLayout(revision: 1, pads: pads)
        let frame = LightingComposer.frame(layout: layout, time: 0, applicationStates: [0: .frontmost, 1: .running])
        #expect(frame[0] == .blue.highlighted)
        #expect(frame[1] == .off)
        #expect(LightingComposer.frame(layout: self.layout(), time: 0, applicationStates: [0: .frontmost])[0] == PadColor(red: 40, green: 20, blue: 10))
    }

    @Test func rendererRestoresAfterEffectAndSendsOnlyDifferences() {
        var time: TimeInterval = 0
        var messages: [[UInt8]] = []
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { messages.append($0) }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(), paused: false)
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        messages.removeAll()
        renderer.press(index: 0, effect: .glow, color: .green)
        #expect(frame[0] == .green)
        #expect(messages.count == 1 && messages[0].count == 13)
        time = 2; renderer.tick()
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        messages.removeAll(); renderer.tick()
        #expect(messages.isEmpty)
    }

    @Test func rendererRateLimitsCoalescesAndBoundsPressBursts() {
        var time: TimeInterval = 0
        var frames = 0
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { _ in frames += 1 }
        renderer.render(layout(LightingSettings(ambientEffect: .rainbow)), paused: false)
        renderer.press(index: 0)
        let before = frames
        for index in 0..<1000 { renderer.press(index: index % 64, effect: .sparkle) }
        time = 0.01; renderer.tick()
        #expect(frames == before)
        time = 0.04; renderer.tick()
        #expect(frames == before + 1)
        time = 10; renderer.render(layout(), paused: false)
        let staticCount = frames
        time = 20; renderer.tick()
        #expect(frames == staticCount)
    }

    @Test func pauseStopRepaintModelAndRevisionCancelObsoleteLayers() {
        var time: TimeInterval = 0
        var model = DeviceModel.miniMK3
        var messages: [[UInt8]] = []
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { model }, send: { messages.append($0) }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(), paused: false)
        renderer.press(index: 0); renderer.setStatus(index: 0, status: .failure)
        renderer.render(layout(revision: 2), paused: false)
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        renderer.press(index: 0); renderer.repaint()
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        renderer.render(layout(), paused: true)
        renderer.press(index: 0); renderer.flash(index: 0, color: .green); renderer.setStatus(index: 0, status: .success)
        #expect(frame.values.allSatisfy { $0 == .off })
        renderer.render(layout(), paused: false)
        renderer.stop()
        #expect(frame.values.allSatisfy { $0 == .off })
        messages.removeAll(); time = 5; renderer.tick(); renderer.press(index: 0); renderer.setAudioLevel(1)
        #expect(messages.isEmpty)
        renderer.render(layout(), paused: false)
        renderer.press(index: 0)
        model = .proMK3; time = 6; renderer.tick()
        #expect(frame.count == 105 && frame.values.allSatisfy { $0 == .off })
    }

    @Test func animationTaskDoesNotRetainRenderer() async throws {
        weak var weakRenderer: LEDRenderer?
        do {
            let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in })
            weakRenderer = renderer
            renderer.render(layout(LightingSettings(ambientEffect: .rainbow)), paused: false)
        }
        try await Task.sleep(for: .milliseconds(60))
        #expect(weakRenderer == nil)
    }
}

extension LightingTests {
    @Test func coalescedAudioUpdateEventuallyPublishesWithoutPermanentMotion() async throws {
        var time: TimeInterval = 0
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in }, clock: { time })
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(LightingSettings(ambientEffect: .audioMeter, accentColor: .green)), paused: false)
        renderer.setAudioLevel(0)
        time = 0.01; renderer.setAudioLevel(1)
        time = 0.04
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while frame[63] != .green, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(frame[63] == .green)
        renderer.stop(clear: false)
    }

    @Test func oldestPressIsDiscardedWhenNewBurstsReachTheBound() {
        var time: TimeInterval = 0
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(), paused: false)
        renderer.press(index: 0, effect: .ripple)
        for _ in 0..<24 { renderer.press(index: 63, effect: .glow) }
        time = 0.15; renderer.tick()
        #expect(frame[1] == .off && frame[8] == .off)
        #expect(frame[63] != .off)
    }

    @Test func noneOverrideSuppressesPageEffectAndOuterPressDoesNotAnimateGrid() {
        var time: TimeInterval = 0
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(LightingSettings(pressEffect: .ripple), bindingEffect: PressEffect.none), paused: false)
        renderer.press(index: 0)
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        renderer.press(index: 64, effect: .ripple, color: .green)
        #expect(frame[64] == .green)
        time = 0.15; renderer.tick()
        #expect(frame[1] == .off)
    }

    @Test func settingsRejectInvalidNumbersAndPixelsAndCompositionStaysSevenBit() throws {
        for invalid in [LightingSettings(brightness: .nan), LightingSettings(brightness: -0.1), LightingSettings(brightness: 1.1),
                        LightingSettings(speed: .infinity), LightingSettings(speed: 0.1), LightingSettings(speed: 4),
                        LightingSettings(gridArtwork: [.blue]), LightingSettings(accentColor: PadColor(red: 128, green: 0, blue: 0))] {
            #expect(throws: (any Error).self) { try invalid.validate() }
        }
        let frame = LightingComposer.frame(layout: layout(LightingSettings(ambientEffect: .rainbow, brightness: 2, speed: .nan)), time: .infinity)
        #expect(frame.values.allSatisfy { $0.red <= 127 && $0.green <= 127 && $0.blue <= 127 })
        #expect(try JSONDecoder().decode(LightingSettings.self, from: JSONEncoder().encode(LightingSettings())) == LightingSettings())
    }
}

extension LightingTests {
    @Test func legacyFlashRestoresAtItsOwnDeadlineAndCannotRepaintAfterStop() async throws {
        var time: TimeInterval = 0
        var frame: [Int: PadColor] = [:]
        var messages: [[UInt8]] = []
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { messages.append($0) }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(), paused: false)
        renderer.flash(index: 0, color: .amber, durationNanoseconds: 50_000_000)
        #expect(frame[0] == .amber)
        time = 0.06; renderer.tick()
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
        let automatic = LEDRenderer(model: { .miniMK3 }, send: { messages.append($0) })
        automatic.render(layout(LightingSettings(ambientEffect: .rainbow)), paused: false)
        automatic.flash(index: 0, color: .green)
        automatic.stop(clear: false)
        messages.removeAll()
        try await Task.sleep(for: .milliseconds(160))
        #expect(messages.isEmpty)
    }

    @Test func reactiveOutputIsIndependentPerDeviceAndStopWithoutClearSendsNothing() {
        var time: TimeInterval = 0
        var firstFrame: [Int: PadColor] = [:]
        var secondFrame: [Int: PadColor] = [:]
        var firstMessages: [[UInt8]] = []
        let first = LEDRenderer(model: { .miniMK3 }, send: { firstMessages.append($0) }, clock: { time }, automaticallyAnimate: false)
        let second = LEDRenderer(model: { .proMK3 }, send: { _ in }, clock: { time }, automaticallyAnimate: false)
        first.onFrame = { firstFrame = $0 }; second.onFrame = { secondFrame = $0 }
        first.render(layout(), paused: false); second.render(layout(model: .proMK3), paused: false)
        first.press(index: 0, effect: .cross, color: .green)
        #expect(firstFrame[1] == .green && secondFrame[1] == .off)
        firstMessages.removeAll(); first.stop(clear: false)
        #expect(firstMessages.isEmpty)
        time = 2; first.tick(); second.tick()
        #expect(firstMessages.isEmpty)
        #expect(secondFrame[0] == PadColor(red: 40, green: 20, blue: 10))
    }
}

extension LightingTests {
    @Test func actionStatusRemainsAboveLegacyFlashAndCanBeCleared() {
        var time: TimeInterval = 0
        var frame: [Int: PadColor] = [:]
        let renderer = LEDRenderer(model: { .miniMK3 }, send: { _ in }, clock: { time }, automaticallyAnimate: false)
        renderer.onFrame = { frame = $0 }
        renderer.render(layout(), paused: false)
        renderer.setStatus(index: 0, status: .failure)
        time = 0.04; renderer.flash(index: 0, color: .amber)
        #expect(frame[0] == PadColor(red: 127, green: 15, blue: 10))
        time = 0.08; renderer.setStatus(index: 0, status: nil)
        #expect(frame[0] == .amber)
        time = 1; renderer.tick()
        #expect(frame[0] == PadColor(red: 40, green: 20, blue: 10))
    }
}
