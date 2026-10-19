// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class ActionExecutor {
    private(set) var isRunning = false
    @ObservationIgnored private var executionTask: Task<Void, Never>?
    @ObservationIgnored private var source: CGEventSource?
    @ObservationIgnored private var runner: ActionRunner?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let dependencies: ActionRunner.Dependencies?
    @ObservationIgnored var expandSteps: @MainActor ([MacroStep]) throws -> [MacroStep] = { steps in
        guard !steps.contains(where: { if case .extensionAction = $0 { return true }; return false }) else {
            throw ActionRunnerFailure("Install or enable the extension for this action.")
        }
        return steps
    }
    @ObservationIgnored var performAdditionalStep: (@MainActor (MacroStep) async throws -> Void)?

    init(dependencies: ActionRunner.Dependencies? = nil) {
        self.dependencies = dependencies
    }

    func execute(_ action: BindingAction, targetProcessID: pid_t?, canPostEvents: Bool,
                 completion: @escaping @MainActor (ActionExecutionResult) -> Void) {
        guard executionTask == nil else { completion(.rejectedBusy); return }
        let steps: [MacroStep]
        do { steps = try expandSteps(ActionPlanner.steps(for: action)) }
        catch { completion(.failed(error.localizedDescription)); return }
        guard !steps.isEmpty else { completion(.cancelled); return }
        generation += 1
        let token = generation
        isRunning = true
        // Injected execution backends must not create or release native keyboard events.
        source = dependencies == nil ? CGEventSource(stateID: .combinedSessionState) : nil
        let runner = ActionRunner(dependencies: dependencies ?? .init(
            canPostEvents: { canPostEvents && AXIsProcessTrusted() && CGPreflightPostEventAccess() },
            frontmostProcessID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            perform: { [weak self] step in
                switch step {
                case .script, .httpRequest:
                    guard let performer = self?.performAdditionalStep else { throw ActionRunnerFailure("This action executor is unavailable.") }
                    try await performer(step)
                    return nil
                default: return try await Self.open(step)
                }
            },
            postShortcut: { [weak self] shortcut in try self?.post(shortcut) },
            postText: { [weak self] text in try await self?.postText(text) }))
        self.runner = runner
        executionTask = Task { [weak self] in
            let result = await runner.run(steps, targetProcessID: targetProcessID)
            guard let self, self.generation == token else { return }
            self.releaseModifiers()
            self.source = nil
            self.runner = nil
            self.executionTask = nil
            self.isRunning = false
            completion(result)
        }
    }
    func activeApplicationChanged(processID: pid_t?) { runner?.activeApplicationChanged(processID: processID) }
    func cancel() { runner?.cancel(); executionTask?.cancel(); releaseModifiers() }

    private static func open(_ step: MacroStep) async throws -> Int32? {
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application: NSRunningApplication
        switch step {
        case let .launchApplication(bundleIdentifier):
            guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw ActionRunnerFailure("Application is unavailable: \(bundleIdentifier). Choose an installed application.")
            }
            application = try await workspace.openApplication(at: url, configuration: configuration)
        case let .openWebsite(value):
            guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw ActionRunnerFailure("Invalid website URL. Enter a complete http:// or https:// address.")
            }
            application = try await workspace.open(url, configuration: configuration)
        case let .openFile(target), let .openFolder(target):
            let url: URL
            do { url = try target.resolvedURL() }
            catch { throw ActionRunnerFailure("The saved location is unavailable: \(target.displayPath). Reselect the file or folder in the action editor.") }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ActionRunnerFailure("Resource is missing: \(target.displayPath). Choose its new location.")
            }
            if case .openFolder = step, !isDirectory.boolValue { throw ActionRunnerFailure("Choose a folder for the Open Folder action.") }
            if case .openFile = step, isDirectory.boolValue { throw ActionRunnerFailure("Choose a file for the Open File action.") }
            application = try await workspace.open(url, configuration: configuration)
        default: throw ActionRunnerFailure("Unsupported action.")
        }
        // The open completion may precede the workspace activation notification.
        for _ in 0..<100 {
            try Task.checkCancellation()
            if workspace.frontmostApplication?.processIdentifier == application.processIdentifier { return application.processIdentifier }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ActionRunnerFailure("The opened application did not become active. Activate it and retry.")
    }
    private func post(_ shortcut: Shortcut) throws {
        guard let source else { throw ActionRunnerFailure("Keyboard event source could not be created.") }
        let modifiers = shortcut.modifiers.sorted { $0.sortOrder < $1.sortOrder }
        defer { releaseModifiers() }
        for modifier in modifiers { try postKey(modifier.keyCode, down: true, source: source) }
        try postKey(shortcut.keyCode, down: true, source: source, flags: shortcut.modifiers.eventFlags)
        try postKey(shortcut.keyCode, down: false, source: source, flags: shortcut.modifiers.eventFlags)
        for modifier in modifiers.reversed() { try postKey(modifier.keyCode, down: false, source: source) }
    }
    private func postText(_ text: String) async throws {
        guard let source else { throw ActionRunnerFailure("Keyboard event source could not be created.") }
        let targetProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // One Unicode scalar per event avoids splitting surrogate pairs or truncating long text.
        for scalar in text.unicodeScalars {
            await Task.yield()
            try Task.checkCancellation()
            guard AXIsProcessTrusted() && CGPreflightPostEventAccess() else { throw ActionRunnerPermissionFailure() }
            guard targetProcessID != nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == targetProcessID else {
                throw CancellationError()
            }
            let chunk = Array(String(scalar).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                    throw ActionRunnerFailure("Unicode keyboard event could not be created.")
                }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
        }
    }
    private func releaseModifiers() {
        guard let source else { return }
        for modifier in ShortcutModifier.allCases.reversed() { try? postKey(modifier.keyCode, down: false, source: source) }
    }
    private func postKey(_ keyCode: UInt16, down: Bool, source: CGEventSource, flags: CGEventFlags = []) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
            throw ActionRunnerFailure("Keyboard event could not be created. Retry the action.")
        }
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
