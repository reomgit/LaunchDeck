// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AVFoundation
import Observation

@MainActor
@Observable
final class AudioReactiveMonitor {
    enum Authorization { case notDetermined, authorized, denied }

    struct Dependencies {
        var authorization: () -> Authorization
        var requestPermission: () async -> Bool
        var startCapture: (@escaping @Sendable (Double) -> Void) throws -> Void
        var stopCapture: () -> Void
        var captureIsRunning: () -> Bool = { true }
    }

    private(set) var isEnabled = false
    private(set) var isCapturing = false
    private(set) var level = 0.0
    private(set) var statusMessage = "Microphone off"
    var onLevel: ((Double) -> Void)?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var healthTask: Task<Void, Never>?

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? Self.liveDependencies()
    }

    /// The only entry point allowed to present the system microphone prompt.
    func enable() async {
        guard !isEnabled else { return }
        isEnabled = true
        generation &+= 1
        let requestGeneration = generation
        var authorization = dependencies.authorization()
        if authorization == .notDetermined {
            statusMessage = "Waiting for microphone permission"
            let granted = await dependencies.requestPermission()
            guard isEnabled, generation == requestGeneration else { return }
            authorization = granted ? dependencies.authorization() : .denied
        }
        guard authorization == .authorized else {
            statusMessage = "Microphone permission denied. Allow access in System Settings."
            return
        }
        guard !suspended else {
            statusMessage = "Microphone paused"
            return
        }
        startCapture()
    }

    func disable() {
        isEnabled = false
        stopCapture()
        statusMessage = "Microphone off"
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value {
            stopCapture()
            statusMessage = isEnabled ? "Microphone paused" : "Microphone off"
        } else if isEnabled {
            // Resuming must never call requestPermission, even if authorization changed.
            guard dependencies.authorization() == .authorized else {
                statusMessage = "Microphone permission denied. Allow access in System Settings."
                return
            }
            startCapture()
        }
    }

    private func startCapture() {
        guard isEnabled, !suspended, !isCapturing else { return }
        generation &+= 1
        let captureGeneration = generation
        do {
            try dependencies.startCapture(Self.makeLevelCallback(monitor: self, generation: captureGeneration))
            isCapturing = true
            statusMessage = "Microphone on · loudness only"
            startHealthChecks(generation: captureGeneration)
        } catch {
            // A dependency may have installed a tap before its engine failed to start.
            dependencies.stopCapture()
            generation &+= 1
            isCapturing = false
            setLevel(0)
            statusMessage = "Microphone unavailable: \(error.localizedDescription)"
        }
    }

    private func stopCapture() {
        generation &+= 1
        healthTask?.cancel()
        healthTask = nil
        if isCapturing { dependencies.stopCapture() }
        isCapturing = false
        setLevel(0)
    }

    private func setLevel(_ value: Double) {
        let bounded = value.isFinite ? min(1, max(0, value)) : 0
        guard level != bounded else { return }
        level = bounded
        onLevel?(bounded)
    }

    /// Constructed outside actor isolation so the audio thread never inherits MainActor.
    private nonisolated static func makeLevelCallback(
        monitor: AudioReactiveMonitor, generation: UInt64
    ) -> @Sendable (Double) -> Void {
        { [weak monitor] value in
            Task { @MainActor [weak monitor] in
                guard let monitor, monitor.generation == generation,
                      monitor.isEnabled, monitor.isCapturing, !monitor.suspended else { return }
                guard monitor.validateCapture() else { return }
                monitor.setLevel(value)
            }
        }
    }

    @discardableResult private func validateCapture() -> Bool {
        if dependencies.authorization() != .authorized {
            stopCapture()
            statusMessage = "Microphone permission denied. Allow access in System Settings."
            return false
        }
        if !dependencies.captureIsRunning() {
            stopCapture()
            statusMessage = "Microphone unavailable. Check the selected input device."
            return false
        }
        return true
    }

    private func startHealthChecks(generation captureGeneration: UInt64) {
        healthTask?.cancel()
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == captureGeneration,
                      self.isCapturing, self.validateCapture() else { return }
            }
        }
    }

    isolated deinit {
        healthTask?.cancel()
        if isCapturing { dependencies.stopCapture() }
    }

    private static func liveDependencies() -> Dependencies {
        let capture = MicrophoneLoudnessCapture()
        return Dependencies(authorization: {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .authorized
            case .notDetermined: .notDetermined
            default: .denied
            }
        }, requestPermission: {
            await AVCaptureDevice.requestAccess(for: .audio)
        }, startCapture: { try capture.start(onLevel: $0) }, stopCapture: {
            capture.stop()
        }, captureIsRunning: { capture.isRunning })
    }
}

/// Owns the input engine; PCM exists only inside the nonisolated tap callback.
@MainActor
private final class MicrophoneLoudnessCapture {
    private var engine: AVAudioEngine?
    private var hasTap = false
    var isRunning: Bool { engine?.isRunning == true }

    func start(onLevel: @escaping @Sendable (Double) -> Void) throws {
        stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Invalid hardware formats can trigger an Objective-C exception in installTap.
        guard format.channelCount > 0, format.sampleRate.isFinite, format.sampleRate > 0,
              format.commonFormat == .pcmFormatFloat32 else {
            throw CaptureError.unavailableFormat
        }
        self.engine = engine
        // nil preserves the node's hardware format rather than forcing a mismatched one.
        input.installTap(onBus: 0, bufferSize: 2048, format: nil, block: Self.makeTap(onLevel: onLevel))
        hasTap = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        guard let engine else { return }
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0) }
        hasTap = false
        self.engine = nil
    }

    private nonisolated static func makeTap(
        onLevel: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frames > 0, channelCount > 0 else { return }
            var squaredChannelLevels = 0.0
            for channel in 0..<channelCount {
                let samples = channels[channel]
                let channelRMS = AudioLevel.rms((0..<frames).lazy.map { samples[$0 * buffer.stride] })
                squaredChannelLevels += channelRMS * channelRMS
            }
            let rms = sqrt(squaredChannelLevels / Double(channelCount))
            onLevel(AudioLevel.normalized(rms: rms))
        }
    }

    isolated deinit { stop() }

    private enum CaptureError: LocalizedError {
        case unavailableFormat
        var errorDescription: String? { "No supported microphone input format is available." }
    }
}
