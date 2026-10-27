// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class ShortcutCaptureSession {
    enum State: Equatable {
        case idle
        case capturing
        case accessibilityRequired
        case inputMonitoringRequired
        case unavailable(String)
    }

    private(set) var pendingShortcut: Shortcut?
    private(set) var state: State = .idle

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?

    func begin(initialShortcut: Shortcut, accessibilityTrusted: Bool) {
        cancel()
        pendingShortcut = initialShortcut

        guard accessibilityTrusted else {
            state = .accessibilityRequired
            return
        }

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            guard CGPreflightListenEventAccess() else {
                state = .inputMonitoringRequired
                return
            }
        }

        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let session = Unmanaged<ShortcutCaptureSession>.fromOpaque(userInfo).takeUnretainedValue()
                // This tap's source is attached only to the main run loop.
                let consumed = MainActor.assumeIsolated {
                    session.handle(type: type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fail("Keyboard capture could not start.")
            return
        }

        tap = newTap
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            fail("Keyboard capture could not start because its event source was unavailable.")
            return
        }

        source = newSource
        let mainRunLoop = CFRunLoopGetMain()
        CFRunLoopAddSource(mainRunLoop, newSource, .commonModes)
        guard CFRunLoopContainsSource(mainRunLoop, newSource, .commonModes) else {
            fail("Keyboard capture could not start because its event source could not be installed.")
            return
        }

        CGEvent.tapEnable(tap: newTap, enable: true)
        guard CGEvent.tapIsEnabled(tap: newTap) else {
            fail("Keyboard capture could not be enabled.")
            return
        }

        state = .capturing
    }

    func finish() -> Shortcut? {
        let result = state == .capturing ? pendingShortcut : nil
        cancel()
        return result
    }

    func cancel() {
        stopTap()
        pendingShortcut = nil
        state = .idle
    }

    /// Returns whether the event should be consumed by the capture session.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            fail("macOS stopped keyboard capture.")
            return false
        }

        guard state == .capturing else { return false }

        if type == .keyDown {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if !Self.modifierKeyCodes.contains(keyCode) {
                var modifiers = Set<ShortcutModifier>()
                let flags = event.flags
                if flags.contains(.maskCommand) { modifiers.insert(.command) }
                if flags.contains(.maskAlternate) { modifiers.insert(.option) }
                if flags.contains(.maskControl) { modifiers.insert(.control) }
                if flags.contains(.maskShift) { modifiers.insert(.shift) }

                let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
                let label: String
                switch keyCode {
                case 53:
                    label = "ESC"
                case 48:
                    label = "TAB"
                case 36:
                    label = "RETURN"
                case 76:
                    label = "ENTER"
                default:
                    if let characters,
                       !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       characters.rangeOfCharacter(from: .controlCharacters) == nil {
                        label = characters.uppercased()
                    } else {
                        label = "Key \(keyCode)"
                    }
                }
                pendingShortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
            }
        }

        // Key-up and flags-changed events are also consumed during capture.
        return true
    }

    private func fail(_ message: String) {
        stopTap()
        state = .unavailable(message)
    }

    private func stopTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    @MainActor deinit {
        stopTap()
    }
}
