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
        case unavailable(String)
    }

    private(set) var pendingShortcut: Shortcut?
    private(set) var state: State = .idle

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?

    func begin(initialShortcut: Shortcut) {
        cancel()
        pendingShortcut = initialShortcut

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            guard CGPreflightListenEventAccess() else {
                state = .unavailable("Input Monitoring access is required. Enable LaunchDeck in System Settings → Privacy & Security → Input Monitoring.")
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
                return MainActor.assumeIsolated {
                    session.handle(type: type, event: event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            fail("Keyboard capture could not start. Check Input Monitoring in System Settings → Privacy & Security.")
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
            fail("Keyboard capture could not start. Check Input Monitoring in System Settings → Privacy & Security.")
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            fail("Keyboard capture stopped. Check Input Monitoring in System Settings → Privacy & Security, then try again.")
            return Unmanaged.passUnretained(event)
        }

        guard state == .capturing else { return Unmanaged.passUnretained(event) }

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
                if keyCode == 53 {
                    label = "ESC"
                } else if let characters, !characters.isEmpty {
                    label = characters.uppercased()
                } else {
                    label = "Key \(keyCode)"
                }
                pendingShortcut = Shortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
            }
        }

        // Key-up and flags-changed events are also consumed during capture.
        return nil
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
        source = nil
        tap = nil
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    @MainActor deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
