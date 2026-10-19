// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import Foundation
import Testing
import Darwin
@testable import LaunchDeckCore

@MainActor
struct ScriptExecutionTests {
    private func withStore(_ body: (ScriptApprovalStore, URL) async throws -> Void) async throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await body(ScriptApprovalStore(directory: directory), directory)
    }

    @Test("Scripts require local enabling; changed content loses its approval")
    func approvalAndChange() async throws {
        try await withStore { store, directory in
            var script = ScriptAction(source: .inline("printf original"), language: .shell)
            let executor = ScriptExecutor(approvals: store)
            do { _ = try await executor.run(script); Issue.record("Unapproved script ran") }
            catch { #expect(error.localizedDescription.contains("Enable")) }
            try store.setEnabled(script, enabled: true)
            #expect(try await executor.run(script).standardOutput == "original")
            script.source = .inline("printf changed")
            #expect(!store.isEnabled(script))
            let restarted = ScriptApprovalStore(directory: directory)
            #expect(!restarted.isEnabled(script))
        }
    }

    @Test("Shell arguments remain literal and Unicode output is retained")
    func literalArguments() async throws {
        try await withStore { store, _ in
            let value = "日本語 ; printf WRONG"
            let script = ScriptAction(source: .inline("printf '%s' \"$1\""), language: .shell, arguments: [value])
            try store.setEnabled(script, enabled: true)
            let output = try await ScriptExecutor(approvals: store).run(script)
            #expect(output.standardOutput == value)
            #expect(output.exitCode == 0)
        }
    }

    @Test("Nonzero exits report stderr and do not claim success")
    func failedExit() async throws {
        try await withStore { store, _ in
            let script = ScriptAction(source: .inline("printf reason >&2; exit 7"), language: .shell)
            try store.setEnabled(script, enabled: true)
            do { _ = try await ScriptExecutor(approvals: store).run(script); Issue.record("Expected failed exit") }
            catch { #expect(error.localizedDescription.contains("7")); #expect(error.localizedDescription.contains("reason")) }
        }
    }

    @Test("Bookmarked script files run with positional arguments")
    func scriptFile() async throws {
        try await withStore { store, directory in
            let url = directory.appending(path: "script.sh")
            try Data("printf '%s' \"$1\"".utf8).write(to: url)
            let script = ScriptAction(source: .file(try FileTarget(url: url)), language: .shell, arguments: ["file argument"])
            try store.setEnabled(script, enabled: true)
            #expect(try await ScriptExecutor(approvals: store).run(script).standardOutput == "file argument")
        }
    }

    @Test("Timeout terminates the script instead of waiting for its full delay")
    func timeout() async throws {
        try await withStore { store, _ in
            let script = ScriptAction(source: .inline("sleep 30"), language: .shell, timeoutSeconds: 1)
            try store.setEnabled(script, enabled: true)
            let start = ContinuousClock.now
            do { _ = try await ScriptExecutor(approvals: store).run(script); Issue.record("Expected timeout") }
            catch { #expect(error.localizedDescription.contains("timed out")) }
            #expect(start.duration(to: .now) < .seconds(5))
        }
    }

    @Test("AppleScript permission failure is checked before interpreter launch")
    func automationDenied() async throws {
        try await withStore { store, _ in
            let script = ScriptAction(source: .inline("return \"ok\""), language: .appleScript, targetBundleIdentifiers: ["test.app"])
            try store.setEnabled(script, enabled: true)
            let executor = ScriptExecutor(approvals: store, automationPermission: { _ in false })
            do { _ = try await executor.run(script); Issue.record("Expected Automation rejection") }
            catch { #expect(error.localizedDescription.contains("Automation")) }
            #expect(executor.runningProcessID == nil)
        }
    }

    @Test("Output is bounded without deadlocking a verbose script")
    func boundedOutput() async throws {
        try await withStore { store, _ in
            let script = ScriptAction(source: .inline("printf '%010000d' 1"), language: .shell)
            try store.setEnabled(script, enabled: true)
            let output = try await ScriptExecutor(approvals: store, outputLimit: 32).run(script)
            #expect(output.standardOutput.utf8.count == 32)
            #expect(output.outputTruncated)
        }
    }
    @Test("Cancellation stops interpreter and descendants promptly")
    func cancellationStopsProcessTree() async throws {
        try await withStore { store, directory in
            let marker = directory.appending(path: "child.pid")
            let script = ScriptAction(source: .inline("sleep 30 & child=$!; printf '%s' \"$child\" > \"$1\"; wait"), language: .shell, arguments: [marker.path])
            try store.setEnabled(script, enabled: true)
            let executor = ScriptExecutor(approvals: store)
            let task = Task { try await executor.run(script) }
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(for: .milliseconds(10)) }
            let child = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
            task.cancel()
            do { _ = try await task.value; Issue.record("Cancelled process succeeded") } catch { #expect(error is CancellationError) }
            for _ in 0..<100 where kill(child, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(kill(child, 0) == -1)
            #expect(executor.runningProcessID == nil)
        }
    }
    @Test("Editing a bookmarked script invalidates local enabling")
    func changedFile() async throws {
        try await withStore { store, directory in
            let file = directory.appending(path: "editable.sh")
            try Data("printf original".utf8).write(to: file)
            let script = ScriptAction(source: .file(try FileTarget(url: file)), language: .shell)
            try store.setEnabled(script, enabled: true)
            #expect(store.isEnabled(script))
            try Data("printf changed".utf8).write(to: file)
            #expect(!store.isEnabled(script))
        }
    }

    @Test("Detached TERM-ignoring children cannot outlive a completed script")
    func detachedChildCleanup() async throws {
        try await withStore { store, directory in
            let marker = directory.appending(path: "detached.pid")
            let script = ScriptAction(source: .inline("trap '' TERM; sleep 30 >/dev/null 2>&1 & child=$!; printf '%s' \"$child\" > \"$1\"; exit 0"), language: .shell, arguments: [marker.path])
            try store.setEnabled(script, enabled: true)
            _ = try await ScriptExecutor(approvals: store).run(script)
            let child = try #require(Int32(String(contentsOf: marker, encoding: .utf8)))
            for _ in 0..<100 where kill(child, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
            #expect(kill(child, 0) == -1)
        }
    }
    @Test("File bytes are captured before waiting for Automation permission")
    func immutableFileExecution() async throws {
        try await withStore { store, directory in
            let file = directory.appending(path: "mutable.applescript")
            try Data("return \"approved\"".utf8).write(to: file)
            let script = ScriptAction(source: .file(try FileTarget(url: file)), language: .appleScript, targetBundleIdentifiers: ["test.app"])
            try store.setEnabled(script, enabled: true)
            let executor = ScriptExecutor(approvals: store, automationPermission: { _ in
                try? Data("return \"changed\"".utf8).write(to: file)
                return true
            })
            #expect(try await executor.run(script).standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "approved")
            #expect(!store.isEnabled(script))
        }
    }
    @Test("Parameterized recipes can enable multiple exact fingerprints sharing an ID")
    func multipleExactApprovals() async throws {
        try await withStore { store, directory in
            let first = ScriptAction(source: .inline("printf '%s' \"$1\""), language: .shell, arguments: ["one"])
            var second = first; second.arguments = ["two"]
            try store.setEnabled(first, enabled: true); try store.setEnabled(second, enabled: true)
            #expect(store.isEnabled(first)); #expect(store.isEnabled(second))
            let restarted = ScriptApprovalStore(directory: directory)
            #expect(restarted.isEnabled(first)); #expect(restarted.isEnabled(second))
            try store.setEnabled(second, enabled: false)
            #expect(store.isEnabled(first)); #expect(!store.isEnabled(second))
        }
    }

    @Test("Captured shell files preserve their original positional script path")
    func shellFilePath() async throws {
        try await withStore { store, directory in
            let file = directory.appending(path: "path.sh")
            try Data("printf '%s' \"$0\"".utf8).write(to: file)
            let script = ScriptAction(source: .file(try FileTarget(url: file)), language: .shell)
            try store.setEnabled(script, enabled: true)
            let output = try await ScriptExecutor(approvals: store).run(script).standardOutput
            let resolvedPath = try FileTarget(url: file).resolvedURL().path
            #expect(output == resolvedPath)
        }
    }
    @Test("Script capture rejects oversized and nonregular files")
    func boundedFileReader() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "big.sh")
        try Data(repeating: 65, count: 101).write(to: file)
        #expect(throws: ScriptExecutionFailure.self) { try ScriptFileReader.read(file, limit: 100) }
        #expect(throws: ScriptExecutionFailure.self) { try ScriptFileReader.read(directory) }
    }

}
