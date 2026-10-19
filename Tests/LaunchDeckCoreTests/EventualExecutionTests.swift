// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import LaunchDeckCore

@MainActor struct EventualExecutionTests {
    @Test func expandedKeyboardRecipesRetainPermissionChecks() async throws {
        var performed = 0
        var posted = 0
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { false }, frontmostProcessID: { 42 }, perform: { _ in performed += 1; return nil }, postShortcut: { _ in posted += 1 }, postText: { _ in posted += 1 }))
        executor.expandSteps = { _ in [.openWebsite("https://example.com"), .text("recipe")] }
        var result: ActionExecutionResult?
        executor.execute(.step(.extensionAction(.init(extensionID: "test", actionID: "recipe"))), targetProcessID: 42, canPostEvents: false) { result = $0 }
        for _ in 0..<100 where result == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(result == .rejectedPermission)
        #expect(performed == 1 && posted == 0)
    }
    @Test func expandedRecipesCancelOnUnexpectedFocusChanges() async throws {
        var posted = false
        var reference: ActionExecutor?
        let script = ScriptAction(source: .inline("printf test"), language: .shell)
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 42 }, perform: { _ in reference?.activeApplicationChanged(processID: 99); return nil }, postShortcut: { _ in posted = true }, postText: { _ in posted = true }))
        reference = executor
        executor.expandSteps = { _ in [.script(script), .shortcut(.copy)] }
        var result: ActionExecutionResult?
        executor.execute(.step(.extensionAction(.init(extensionID: "test", actionID: "recipe"))), targetProcessID: 42, canPostEvents: true) { result = $0 }
        for _ in 0..<100 where result == nil { try await Task.sleep(for: .milliseconds(2)) }
        #expect(result == .cancelled && !posted)
    }
    @Test func missingExtensionsReportActionableFailure() {
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { false }, frontmostProcessID: { nil }, perform: { _ in Issue.record("Should not perform"); return nil }, postShortcut: { _ in }, postText: { _ in }))
        var result: ActionExecutionResult?
        executor.execute(.step(.extensionAction(.init(extensionID: "missing", actionID: "missing"))), targetProcessID: nil, canPostEvents: false) { result = $0 }
        guard case let .failed(message) = result else { Issue.record("Missing extension must fail"); return }
        #expect(message.contains("Install or enable"))
    }
}
