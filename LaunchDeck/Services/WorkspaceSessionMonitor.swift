// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AppKit
import CoreGraphics
import Foundation

/// Sleep and fast-user switching are independent reasons to suspend input.
@MainActor
final class WorkspaceSessionMonitor {
    private(set) var isAvailable = true
    var onAvailabilityChanged: (@MainActor (Bool) -> Void)?

    private let notificationCenter: NotificationCenter
    private let sessionIsActive: @MainActor () -> Bool
    private var observers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var isSessionActive = true

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         sessionIsActive: @escaping @MainActor () -> Bool = WorkspaceSessionMonitor.activeConsoleSession) {
        self.notificationCenter = notificationCenter
        self.sessionIsActive = sessionIsActive
    }

    isolated deinit { stop() }

    func start() {
        guard observers.isEmpty else { return }
        isSleeping = false
        isSessionActive = sessionIsActive()
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The observer's explicit main queue guarantees this isolation.
                // Handle synchronously so queued presses cannot precede suspension.
                MainActor.assumeIsolated { self?.receive(name) }
            })
        }
        publishAvailability()
    }

    func stop() {
        for observer in observers { notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    private func receive(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification: isSleeping = true
        case NSWorkspace.didWakeNotification: isSleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: isSessionActive = false
        case NSWorkspace.sessionDidBecomeActiveNotification: isSessionActive = true
        default: return
        }
        publishAvailability()
    }

    private func publishAvailability() {
        let available = !isSleeping && isSessionActive
        guard available != isAvailable else { return }
        isAvailable = available
        onAvailabilityChanged?(available)
    }

    private static func activeConsoleSession() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true
            && session[kCGSessionLoginDoneKey as String] as? Bool == true
    }
}
