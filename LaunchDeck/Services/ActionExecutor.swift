// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import CoreGraphics
import Foundation
import Observation

enum ActionExecutionResult: Equatable {
    case dispatched
    case rejectedBusy
    case rejectedPermission
    case cancelled
}

@MainActor
@Observable
final class ActionExecutor {
    private(set) var isRunning = false

    @ObservationIgnored private var executionTask: Task<Void, Never>?
    @ObservationIgnored private var source: CGEventSource?

    func execute(
        _ action: BindingAction,
        targetProcessID: pid_t?,
        canPostEvents: Bool,
        targetIsStillFrontmost: @escaping @MainActor (pid_t?) -> Bool,
        completion: @escaping @MainActor (ActionExecutionResult) -> Void
    ) {
        guard executionTask == nil else {
            completion(.rejectedBusy)
            return
        }
        guard canPostEvents else {
            completion(.rejectedPermission)
            return
        }

        let steps = ActionPlanner.steps(for: action)
        guard !steps.isEmpty else {
            completion(.cancelled)
            return
        }

        isRunning = true
        source = CGEventSource(stateID: .combinedSessionState)
        executionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.releaseModifiers()
                self.source = nil
                self.executionTask = nil
                self.isRunning = false
            }

            for step in steps {
                guard !Task.isCancelled, targetIsStillFrontmost(targetProcessID) else {
                    completion(.cancelled)
                    return
                }

                switch step {
                case let .shortcut(shortcut):
                    guard post(shortcut) else {
                        completion(.cancelled)
                        return
                    }
                case let .delay(milliseconds):
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
                    } catch {
                        completion(.cancelled)
                        return
                    }
                }
            }
            completion(.dispatched)
        }
    }

    func cancel() {
        executionTask?.cancel()
        releaseModifiers()
    }

    private func post(_ shortcut: Shortcut) -> Bool {
        guard let source else { return false }
        let modifiers = shortcut.modifiers.sorted { $0.sortOrder < $1.sortOrder }
        for modifier in modifiers {
            postKey(modifier.keyCode, down: true, source: source)
        }
        postKey(shortcut.keyCode, down: true, source: source, flags: shortcut.modifiers.eventFlags)
        postKey(shortcut.keyCode, down: false, source: source, flags: shortcut.modifiers.eventFlags)
        for modifier in modifiers.reversed() {
            postKey(modifier.keyCode, down: false, source: source)
        }
        return true
    }

    private func releaseModifiers() {
        guard let source else { return }
        for modifier in ShortcutModifier.allCases.reversed() {
            postKey(modifier.keyCode, down: false, source: source)
        }
    }

    private func postKey(_ keyCode: UInt16, down: Bool, source: CGEventSource, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

private extension ShortcutModifier {
    var keyCode: UInt16 {
        switch self {
        case .command: 55
        case .option: 58
        case .control: 59
        case .shift: 56
        }
    }

    var sortOrder: Int {
        switch self {
        case .control: 0
        case .option: 1
        case .shift: 2
        case .command: 3
        }
    }
}

private extension Set where Element == ShortcutModifier {
    var eventFlags: CGEventFlags {
        reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
    }
}
