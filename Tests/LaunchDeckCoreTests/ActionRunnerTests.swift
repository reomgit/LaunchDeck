import Testing
@testable import LaunchDeckCore

@MainActor
struct ActionRunnerTests {
    @Test func keyboardPermissionIsPerStep() async {
        var opened = false
        let runner = ActionRunner(dependencies: .init(canPostEvents: { false }, frontmostProcessID: { 1 }, perform: { _ in opened = true; return 1 }, postShortcut: { _ in }, postText: { _ in }))
        let result = await runner.run([.openWebsite("https://example.com"), .shortcut(.copy)], targetProcessID: 1)
        #expect(opened)
        #expect(result == .rejectedPermission)
    }
    @Test func stopsAtFailure() async {
        var count = 0
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in throw ActionRunnerFailure("Missing application") }, postShortcut: { _ in count += 1 }, postText: { _ in }))
        let result = await runner.run([.launchApplication(bundleIdentifier: "missing"), .shortcut(.copy)], targetProcessID: 1)
        #expect(result == .failed("Missing application"))
        #expect(count == 0)
    }
    @Test func expectedHandoffAllowsKeyboard() async {
        var frontmost: Int32? = 1
        var posted = false
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { frontmost }, perform: { _ in frontmost = 2; return 2 }, postShortcut: { _ in posted = true }, postText: { _ in }))
        #expect(await runner.run([.launchApplication(bundleIdentifier: "app"), .shortcut(.copy)], targetProcessID: 1) == .dispatched)
        #expect(posted)
    }
    @Test func unexpectedFocusCancels() async {
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 2 }, perform: { _ in nil }, postShortcut: { _ in Issue.record("Should not dispatch") }, postText: { _ in }))
        #expect(await runner.run([.shortcut(.copy)], targetProcessID: 1) == .cancelled)
    }
}

@MainActor
struct ActionRunnerSequenceTests {
    @Test func maintainsOrderAndDelay() async {
        var events: [String] = []
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in events.append("open"); return 1 }, postShortcut: { _ in events.append("shortcut") }, postText: { text in events.append(text) }, sleep: { milliseconds in events.append("delay:\(milliseconds)") }))
        let result = await runner.run([.openWebsite("https://example.com"), .delay(milliseconds: 25), .text("日本語 😀"), .shortcut(.paste)], targetProcessID: 1)
        #expect(result == .dispatched)
        #expect(events == ["open", "delay:25", "日本語 😀", "shortcut"])
    }
    @Test func busyAndCancellationDuringDelay() async {
        var continuation: CheckedContinuation<Void, Never>?
        var posted = false
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in 1 }, postShortcut: { _ in posted = true }, postText: { _ in }, sleep: { _ in await withCheckedContinuation { continuation = $0 } }))
        let task = Task { await runner.run([.delay(milliseconds: 1), .shortcut(.copy)], targetProcessID: 1) }
        while continuation == nil { await Task.yield() }
        #expect(await runner.run([.shortcut(.paste)], targetProcessID: 1) == .rejectedBusy)
        runner.cancel()
        continuation?.resume()
        #expect(await task.value == .cancelled)
        #expect(!posted)
        #expect(await runner.run([.shortcut(.copy)], targetProcessID: 1) == .dispatched)
    }
    @Test func unexpectedActivationDuringDelayCancels() async {
        var continuation: CheckedContinuation<Void, Never>?
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in 1 }, postShortcut: { _ in Issue.record("Unexpected keyboard event") }, postText: { _ in }, sleep: { _ in await withCheckedContinuation { continuation = $0 } }))
        let task = Task { await runner.run([.delay(milliseconds: 1), .shortcut(.copy)], targetProcessID: 1) }
        while continuation == nil { await Task.yield() }
        runner.activeApplicationChanged(processID: 2)
        continuation?.resume()
        #expect(await task.value == .cancelled)
    }
}

@MainActor
struct ActionRunnerHandoffTests {
    @Test func cancellationDuringOpenStopsKeyboard() async {
        var continuation: CheckedContinuation<Int32?, Never>?
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 2 }, perform: { _ in await withCheckedContinuation { continuation = $0 } }, postShortcut: { _ in Issue.record("Must stop after cancellation") }, postText: { _ in }))
        let task = Task { await runner.run([.launchApplication(bundleIdentifier: "app"), .shortcut(.copy)], targetProcessID: 1) }
        while continuation == nil { await Task.yield() }
        runner.cancel()
        continuation?.resume(returning: 2)
        #expect(await task.value == .cancelled)
    }
    @Test func permissionRevokedBeforeLaterKeyboardStep() async {
        var allowed = true
        var count = 0
        let runner = ActionRunner(dependencies: .init(canPostEvents: { allowed }, frontmostProcessID: { 1 }, perform: { _ in 1 }, postShortcut: { _ in count += 1 }, postText: { _ in }, sleep: { _ in allowed = false }))
        #expect(await runner.run([.shortcut(.copy), .delay(milliseconds: 1), .text("Hello")], targetProcessID: 1) == .rejectedPermission)
        #expect(count == 1)
    }
    @Test func reportedExpectedActivationAllowsKeyboard() async {
        var continuation: CheckedContinuation<Int32?, Never>?
        let frontmost = ActionTestFocus()
        var posted = false
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { frontmost.processID }, perform: { _ in await withCheckedContinuation { continuation = $0 } }, postShortcut: { _ in posted = true }, postText: { _ in }))
        let task = Task { await runner.run([.launchApplication(bundleIdentifier: "app"), .shortcut(.copy)], targetProcessID: 1) }
        while continuation == nil { await Task.yield() }
        frontmost.processID = 2
        runner.activeApplicationChanged(processID: 2)
        continuation?.resume(returning: 2)
        #expect(await task.value == .dispatched)
        #expect(posted)
    }
    @Test func reportedUnrelatedActivationDuringHandoffStopsKeyboard() async {
        var continuation: CheckedContinuation<Int32?, Never>?
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 2 }, perform: { _ in await withCheckedContinuation { continuation = $0 } }, postShortcut: { _ in Issue.record("Must stop after unrelated activation") }, postText: { _ in }))
        let task = Task { await runner.run([.launchApplication(bundleIdentifier: "app"), .shortcut(.copy)], targetProcessID: 1) }
        while continuation == nil { await Task.yield() }
        runner.activeApplicationChanged(processID: 3)
        continuation?.resume(returning: 2)
        #expect(await task.value == .cancelled)
    }
    @Test func asyncTextCancellationAndPermissionFailureAreReported() async {
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in 1 }, postShortcut: { _ in }, postText: { _ in throw ActionRunnerPermissionFailure() }))
        #expect(await runner.run([.text("Hello")], targetProcessID: 1) == .rejectedPermission)
        let cancelled = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 1 }, perform: { _ in 1 }, postShortcut: { _ in }, postText: { _ in throw CancellationError() }))
        #expect(await cancelled.run([.text("Hello")], targetProcessID: 1) == .cancelled)
    }
}

@MainActor
struct ActionRunnerPlanningTests {
    @Test func navigationIsNotExecutable() {
        #expect(ActionPlanner.steps(for: .navigation(.home)).isEmpty)
        #expect(ActionPlanner.steps(for: .step(.text("Hello"))) == [.text("Hello")])
    }
    @Test func openingResourceDoesNotRequireKeyboardPermission() async {
        let runner = ActionRunner(dependencies: .init(canPostEvents: { false }, frontmostProcessID: { nil }, perform: { _ in 2 }, postShortcut: { _ in Issue.record("Unexpected shortcut") }, postText: { _ in }))
        #expect(await runner.run([.openWebsite("https://example.com")], targetProcessID: nil) == .dispatched)
    }
    @Test func keyboardWithoutTargetCancels() async {
        let runner = ActionRunner(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { nil }, perform: { _ in nil }, postShortcut: { _ in Issue.record("Missing target") }, postText: { _ in }))
        #expect(await runner.run([.shortcut(.copy)], targetProcessID: nil) == .cancelled)
    }
}

@MainActor
private final class ActionTestFocus { var processID: Int32? = 1 }
