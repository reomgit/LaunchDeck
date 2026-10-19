// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import AppKit
import Foundation
import Testing
@testable import LaunchDeckCore

@MainActor
struct WorkspaceSessionTests {
    @Test("Waking does not resume execution while the user session is inactive")
    func overlappingSuspensions() {
        let center = NotificationCenter()
        let monitor = WorkspaceSessionMonitor(notificationCenter: center, sessionIsActive: { true })
        var changes: [Bool] = []
        monitor.onAvailabilityChanged = { changes.append($0) }
        monitor.start()
        defer { monitor.stop() }

        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(changes == [false])
        #expect(!monitor.isAvailable)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(changes == [false, true])
        #expect(monitor.isAvailable)
    }

    @Test("Duplicate notifications and stopping observers do not trigger extra transitions")
    func stoppingAndDuplicates() {
        let center = NotificationCenter()
        let monitor = WorkspaceSessionMonitor(notificationCenter: center, sessionIsActive: { true })
        var changes: [Bool] = []
        monitor.onAvailabilityChanged = { changes.append($0) }
        monitor.start()
        monitor.start()
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(changes == [false])
        monitor.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(changes == [false])
        monitor.start()
        #expect(changes == [false, true])
        monitor.stop()
    }

    @Test("Starting in an inactive session immediately blocks execution")
    func initialInactiveSession() {
        let monitor = WorkspaceSessionMonitor(notificationCenter: NotificationCenter(), sessionIsActive: { false })
        var changes: [Bool] = []
        monitor.onAvailabilityChanged = { changes.append($0) }
        monitor.start()
        defer { monitor.stop() }
        #expect(!monitor.isAvailable)
        #expect(changes == [false])
    }

    @Test("Workspace sleep cancels a running macro before its next keyboard step")
    func cancelsExecution() async throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let center = NotificationCenter()
        let monitor = WorkspaceSessionMonitor(notificationCenter: center, sessionIsActive: { true })
        var waiting: CheckedContinuation<Void, Never>?
        var posted = false
        let executor = ActionExecutor(dependencies: .init(
            canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in 1 },
            postShortcut: { _ in posted = true }, postText: { _ in },
            sleep: { _ in await withCheckedContinuation { waiting = $0 } }))
        let coordinator = AppCoordinator(profileStore: store, sessionMonitor: monitor, actionExecutor: executor)
        defer { coordinator.shutdown() }
        monitor.start()
        var result: ActionExecutionResult?
        executor.execute(.macro([.delay(milliseconds: 1), .shortcut(.copy)]), targetProcessID: 1,
                         canPostEvents: true) { result = $0 }
        while waiting == nil { await Task.yield() }
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(coordinator.isSessionSuspended)
        #expect(coordinator.statusText == "Suspended · waiting for the active user session")
        waiting?.resume()
        while result == nil { await Task.yield() }
        #expect(result == .cancelled)
        #expect(!posted)
        coordinator.isPaused = true
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!coordinator.isSessionSuspended)
        #expect(coordinator.isPaused)
        #expect(coordinator.statusText == "Paused")
    }
}
