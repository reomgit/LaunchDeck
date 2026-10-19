// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import Foundation

enum ActionExecutionResult: Equatable {
    case dispatched, rejectedBusy, rejectedPermission, cancelled
    case failed(String)
}
struct ActionRunnerPermissionFailure: Error {}
struct ActionRunnerFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class ActionRunner {
    struct Dependencies {
        var canPostEvents: @MainActor () -> Bool
        var frontmostProcessID: @MainActor () -> Int32?
        var perform: @MainActor (MacroStep) async throws -> Int32?
        var postShortcut: @MainActor (Shortcut) throws -> Void
        var postText: @MainActor (String) async throws -> Void
        var sleep: @MainActor (Int) async throws -> Void = { milliseconds in
            try await Task.sleep(for: .milliseconds(max(0, milliseconds)))
        }
    }
    private let dependencies: Dependencies
    private var generation = 0
    private(set) var isRunning = false
    private var cancelled = false
    private var expectedProcessID: Int32?
    private var monitorsFocus = false
    private var handingOff = false
    private var handoffObservedProcessIDs: [Int32?] = []
    init(dependencies: Dependencies) { self.dependencies = dependencies }
    func cancel() { cancelled = true }
    func activeApplicationChanged(processID: Int32?) {
        guard isRunning, monitorsFocus else { return }
        if handingOff { handoffObservedProcessIDs.append(processID) }
        else if processID != expectedProcessID { cancelled = true }
    }
    func run(_ steps: [MacroStep], targetProcessID: Int32?) async -> ActionExecutionResult {
        guard !isRunning else { return .rejectedBusy }
        guard !steps.isEmpty else { return .cancelled }
        generation += 1
        let token = generation
        isRunning = true
        cancelled = false
        expectedProcessID = targetProcessID
        monitorsFocus = steps.contains { step in
            switch step { case .shortcut, .text: true; default: false }
        }
        defer { if generation == token { isRunning = false; handingOff = false } }
        do {
            for step in steps {
                guard !cancelled, !Task.isCancelled else { return .cancelled }
                switch step {
                case let .shortcut(shortcut):
                    guard dependencies.canPostEvents() else { return .rejectedPermission }
                    guard expectedProcessID != nil, dependencies.frontmostProcessID() == expectedProcessID else { return .cancelled }
                    try dependencies.postShortcut(shortcut)
                case let .text(text):
                    guard dependencies.canPostEvents() else { return .rejectedPermission }
                    guard expectedProcessID != nil, dependencies.frontmostProcessID() == expectedProcessID else { return .cancelled }
                    try await dependencies.postText(text)
                case let .delay(milliseconds): try await dependencies.sleep(milliseconds)
                case .script, .httpRequest:
                    _ = try await dependencies.perform(step)
                case .extensionAction:
                    throw ActionRunnerFailure("Extension actions must be resolved before execution. Install or enable their extension.")
                case .launchApplication, .openFile, .openFolder, .openWebsite:
                    handingOff = true
                    handoffObservedProcessIDs = []
                    let processID = try await dependencies.perform(step)
                    handingOff = false
                    let previousProcessID = expectedProcessID
                    if let processID { expectedProcessID = processID }
                    if handoffObservedProcessIDs.contains(where: { $0 != expectedProcessID && $0 != previousProcessID }) {
                        cancelled = true
                    }
                }
            }
            return cancelled || Task.isCancelled ? .cancelled : .dispatched
        } catch {
            if cancelled || Task.isCancelled || error is CancellationError { return .cancelled }
            if error is ActionRunnerPermissionFailure { return .rejectedPermission }
            if let failure = error as? ActionRunnerFailure { return .failed(failure.message) }
            return .failed(error.localizedDescription)
        }
    }
}
