// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import LaunchDeckCore

struct AudioReactiveTests {
    @Test func syntheticPCMProducesBoundedRMSLoudness() {
        #expect(AudioLevel.rms([0, 0, 0, 0]) == 0)
        #expect(abs(AudioLevel.rms([1, -1, 1, -1]) - 1) < 0.000001)
        #expect(abs(AudioLevel.rms([0, 1, 0, -1]) - 0.70710678118) < 0.000001)
        #expect(AudioLevel.rms([]) == 0)
        #expect(AudioLevel.rms([.nan, .infinity, -.infinity, 0]) == 0)
        #expect(AudioLevel.normalized(rms: 0) == 0)
        #expect(AudioLevel.normalized(rms: 0.001) == 0)
        #expect(abs(AudioLevel.normalized(rms: 0.1) - 2.0 / 3.0) < 0.000001)
        #expect(AudioLevel.normalized(rms: 1) == 1)
        #expect(AudioLevel.normalized(rms: 10) == 1)
        #expect(AudioLevel.normalized(rms: .nan) == 0)
        #expect(AudioLevel.normalized(rms: .infinity) == 0)
    }

    @MainActor @Test func defaultAndResumeCannotRequestOrCapture() {
        let input = FakeAudioInput()
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        #expect(!monitor.isEnabled)
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        monitor.setSuspended(true)
        monitor.setSuspended(false)
        #expect(input.permissionRequests == 0)
        #expect(input.callbacks.isEmpty)
    }

    @MainActor @Test func explicitEnableRequestsOnceAndDisableRejectsLateSamples() async {
        let input = FakeAudioInput()
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        var observed: [Double] = []
        monitor.onLevel = { observed.append($0) }
        await monitor.enable()
        await monitor.enable()
        #expect(input.permissionRequests == 1)
        #expect(monitor.isEnabled)
        #expect(monitor.isCapturing)
        #expect(input.callbacks.count == 1)
        input.emit(0.75)
        await settleCallbacks()
        #expect(monitor.level == 0.75)
        #expect(observed.last == 0.75)
        monitor.disable()
        #expect(!monitor.isCapturing)
        #expect(!monitor.isEnabled)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        input.emit(0.9)
        await settleCallbacks()
        #expect(monitor.level == 0)
        #expect(observed.last == 0)
    }

    @MainActor @Test func pauseStopsCaptureAndResumeUsesExistingPermission() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        input.emit(0.6)
        await settleCallbacks()
        monitor.setSuspended(true)
        #expect(monitor.isEnabled)
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        input.emit(1)
        await settleCallbacks()
        #expect(monitor.level == 0)
        monitor.setSuspended(false)
        #expect(monitor.isCapturing)
        #expect(input.callbacks.count == 2)
        #expect(input.permissionRequests == 0)
        input.emit(0.8, generation: 0)
        await settleCallbacks()
        #expect(monitor.level == 0)
        input.emit(0.4, generation: 1)
        await settleCallbacks()
        #expect(monitor.level == 0.4)
        monitor.disable()
    }

    @MainActor @Test func deniedAndRevokedPermissionStayVisibleWithoutReprompting() async {
        let input = FakeAudioInput()
        input.authorization = .denied
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        #expect(!monitor.isCapturing)
        #expect(input.permissionRequests == 0)
        #expect(!monitor.statusMessage.isEmpty)
        input.authorization = .authorized
        monitor.disable()
        await monitor.enable()
        #expect(monitor.isCapturing)
        monitor.setSuspended(true)
        input.authorization = .denied
        monitor.setSuspended(false)
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.callbacks.count == 1)
        #expect(input.permissionRequests == 0)
        #expect(monitor.statusMessage.localizedCaseInsensitiveContains("denied"))
        monitor.disable()
    }

    @MainActor @Test func unavailableCaptureStopsPartialResourcesAndShowsError() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        input.captureFails = true
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        #expect(monitor.statusMessage.localizedCaseInsensitiveContains("unavailable"))
        monitor.disable()
    }

    @MainActor @Test func disablingDuringPermissionRequestCannotStartCapture() async {
        let input = FakeAudioInput()
        input.holdPermission = true
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        let task = Task { await monitor.enable() }
        await settleCallbacks()
        #expect(input.permissionRequests == 1)
        monitor.disable()
        input.completePermission(true)
        await task.value
        #expect(!monitor.isEnabled)
        #expect(!monitor.isCapturing)
        #expect(input.callbacks.isEmpty)
    }

    @MainActor @Test func enablingWhileSuspendedWaitsForResume() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        monitor.setSuspended(true)
        await monitor.enable()
        #expect(monitor.isEnabled)
        #expect(!monitor.isCapturing)
        #expect(input.callbacks.isEmpty)
        monitor.setSuspended(false)
        #expect(monitor.isCapturing)
        monitor.disable()
    }

    @MainActor @Test func backgroundSamplesAreSanitizedAndDeliveredToMainActor() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        let callback = input.callbacks[0]
        await Task.detached { callback(.nan) }.value
        await settleCallbacks()
        #expect(monitor.level == 0)
        await Task.detached { callback(3) }.value
        await settleCallbacks()
        #expect(monitor.level == 1)
        monitor.disable()
    }

    @MainActor @Test func liveRevocationStopsCaptureAndClearsLoudness() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        input.emit(0.7)
        await settleCallbacks()
        input.authorization = .denied
        input.emit(0.9)
        await settleCallbacks()
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        #expect(input.permissionRequests == 0)
        #expect(monitor.statusMessage.localizedCaseInsensitiveContains("denied"))
        monitor.disable()
    }

    @MainActor @Test func revocationWithoutFurtherSamplesStopsThroughHealthCheck() async throws {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        input.authorization = .denied
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while monitor.isCapturing && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        #expect(monitor.statusMessage.localizedCaseInsensitiveContains("denied"))
        monitor.disable()
    }

    @MainActor @Test func lostInputStopsCaptureAndClearsLoudness() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        let monitor = AudioReactiveMonitor(dependencies: input.dependencies)
        await monitor.enable()
        input.emit(0.7)
        await settleCallbacks()
        input.captureRunning = false
        input.emit(0.9)
        await settleCallbacks()
        #expect(!monitor.isCapturing)
        #expect(monitor.level == 0)
        #expect(input.stopCalls == 1)
        #expect(monitor.statusMessage.localizedCaseInsensitiveContains("unavailable"))
        monitor.disable()
    }

    @MainActor @Test func releasingMonitorStopsCaptureWithoutRetainingSession() async {
        let input = FakeAudioInput()
        input.authorization = .authorized
        var monitor: AudioReactiveMonitor? = AudioReactiveMonitor(dependencies: input.dependencies)
        weak var releasedMonitor = monitor
        await monitor?.enable()
        await settleCallbacks()
        #expect(monitor?.isCapturing == true)
        monitor = nil
        #expect(releasedMonitor == nil)
        #expect(input.stopCalls == 1)
    }

    @MainActor private func settleCallbacks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class FakeAudioInput {
    var authorization: AudioReactiveMonitor.Authorization = .notDetermined
    var permissionRequests = 0
    var stopCalls = 0
    var captureFails = false
    var captureRunning = true
    var holdPermission = false
    var continuation: CheckedContinuation<Bool, Never>?
    var callbacks: [@Sendable (Double) -> Void] = []

    var dependencies: AudioReactiveMonitor.Dependencies {
        .init(authorization: { self.authorization }, requestPermission: {
            self.permissionRequests += 1
            if self.holdPermission {
                return await withCheckedContinuation { self.continuation = $0 }
            }
            self.authorization = .authorized
            return true
        }, startCapture: { callback in
            self.callbacks.append(callback)
            if self.captureFails { throw InputError.unavailable }
        }, stopCapture: { self.stopCalls += 1 }, captureIsRunning: { self.captureRunning })
    }

    func completePermission(_ granted: Bool) {
        authorization = granted ? .authorized : .denied
        continuation?.resume(returning: granted)
        continuation = nil
    }

    func emit(_ value: Double, generation: Int? = nil) {
        callbacks[generation ?? callbacks.count - 1](value)
    }

    enum InputError: Error { case unavailable }
}
