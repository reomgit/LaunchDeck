// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import AppKit
import Carbon
import Darwin
import Foundation
import Observation

@MainActor @Observable
final class ScriptExecutor {
    private(set) var runningProcessID: pid_t?
    private(set) var lastOutput: ScriptExecutionOutput?
    private let approvals: ScriptApprovalStore
    private let automationPermission: @MainActor (String) -> Bool
    private let outputLimit: Int
    private var runID: UUID?

    init(approvals: ScriptApprovalStore, outputLimit: Int = 1_000_000,
         automationPermission: @escaping @MainActor (String) -> Bool = ScriptExecutor.requestAutomationPermission) {
        self.approvals = approvals; self.outputLimit = max(1, outputLimit)
        self.automationPermission = automationPermission
    }

    func run(_ script: ScriptAction) async throws -> ScriptExecutionOutput {
        try script.validate()
        guard runID == nil else { throw ScriptExecutionFailure("Another script is running.") }
        let token = UUID(); runID = token
        defer { runID = nil; runningProcessID = nil }
        var snapshotDirectory: URL?
        defer { if let snapshotDirectory { try? FileManager.default.removeItem(at: snapshotDirectory) } }
        var capturedContents: Data?
        var arguments: [String]
        switch script.source {
        case let .inline(code):
            arguments = script.language == .shell ? ["/bin/zsh", "-c", code, "LaunchDeck"] : ["/usr/bin/osascript", "-e", code]
        case let .file(target):
            let url: URL
            do { url = try target.resolvedURL() }
            catch { throw ScriptExecutionFailure("Script file is unavailable. Reselect \(target.displayPath).") }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 1_000_000 else {
                throw ScriptExecutionFailure("Choose an existing script file of at most 1 MB.")
            }
            let content = try ScriptFileReader.read(url)
            guard content.count <= 1_000_000 else { throw ScriptExecutionFailure("Script file exceeds the 1 MB review limit.") }
            capturedContents = content
            if script.language == .shell {
                guard let code = String(data: content, encoding: .utf8) else { throw ScriptExecutionFailure("Shell script must contain UTF-8 text.") }
                arguments = ["/bin/zsh", "-c", code, url.path]
            } else {
                let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "LaunchDeck-script-" + token.uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                snapshotDirectory = directory
                let snapshot = directory.appending(path: "script").appendingPathExtension(url.pathExtension)
                try content.write(to: snapshot, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshot.path)
                arguments = ["/usr/bin/osascript", snapshot.path]
            }
        }
        guard approvals.isEnabled(script, fileContents: capturedContents) else {
            throw ScriptExecutionFailure("Enable this script in the control inspector after reviewing its contents. Imported or changed scripts require local enabling.")
        }
        if script.language == .appleScript {
            for target in script.targetBundleIdentifiers where !automationPermission(target) {
                throw ScriptExecutionFailure("Automation permission denied for \(target). Allow LaunchDeck in System Settings → Privacy & Security → Automation.")
            }
        }
        arguments += script.arguments
        let process = ScriptProcess(arguments: arguments, outputLimit: outputLimit)
        let output = try await process.run(timeoutSeconds: script.timeoutSeconds) { [weak self] pid in
            Task { @MainActor in
                guard self?.runID == token else { return }
                self?.runningProcessID = pid
            }
        }
        lastOutput = output
        return output
    }

    private static func requestAutomationPermission(_ identifier: String) -> Bool {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: identifier)
        guard let target = descriptor.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, true) == noErr
    }
}

/// The child gets its own process group, so cancellation also stops descendants.
private final class ScriptProcess: @unchecked Sendable {
    private let arguments: [String]
    private let outputLimit: Int
    private let lock = NSLock()
    private var processID: pid_t = 0
    private var finished = false
    private var cancellation: CancellationCause?
    private enum CancellationCause { case cancelled, timedOut }

    init(arguments: [String], outputLimit: Int) { self.arguments = arguments; self.outputLimit = outputLimit }

    func run(timeoutSeconds: Int, onStart: @escaping @Sendable (pid_t) -> Void) async throws -> ScriptExecutionOutput {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let output = try self.launch(onStart: onStart)
                        continuation.resume(returning: output)
                    } catch { continuation.resume(throwing: error) }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(timeoutSeconds)) {
                    self.cancel(.timedOut)
                }
            }
        } onCancel: { self.cancel(.cancelled) }
    }

    private func launch(onStart: @Sendable (pid_t) -> Void) throws -> ScriptExecutionOutput {
        lock.lock(); let alreadyCancelled = cancellation != nil; lock.unlock()
        if alreadyCancelled { throw CancellationError() }
        var outFD: [Int32] = [0, 0], errFD: [Int32] = [0, 0]
        guard pipe(&outFD) == 0 else { throw ScriptExecutionFailure("Could not open script output pipe.") }
        guard pipe(&errFD) == 0 else {
            close(outFD[0]); close(outFD[1]); throw ScriptExecutionFailure("Could not open script error pipe.")
        }
        let inputFD = open("/dev/null", O_RDONLY)
        guard inputFD >= 0 else {
            (outFD + errFD).forEach { close($0) }
            throw ScriptExecutionFailure("Could not open script input.")
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes); close(inputFD) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawn_file_actions_adddup2(&actions, inputFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, outFD[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errFD[1], STDERR_FILENO)
        for fd in outFD + errFD + [inputFD] { posix_spawn_file_actions_addclose(&actions, fd) }
        var argv = arguments.map { strdup($0) } + [nil]
        defer { argv.compactMap { $0 }.forEach { free($0) } }
        var environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { environment.compactMap { $0 }.forEach { free($0) } }
        var pid: pid_t = 0
        let spawnError = argv.withUnsafeMutableBufferPointer { buffer in
            environment.withUnsafeMutableBufferPointer { env in
                posix_spawn(&pid, arguments[0], &actions, &attributes, buffer.baseAddress!, env.baseAddress!)
            }
        }
        close(outFD[1]); close(errFD[1])
        guard spawnError == 0 else {
            close(outFD[0]); close(errFD[0])
            lock.lock(); finished = true; lock.unlock()
            throw ScriptExecutionFailure("Could not launch script interpreter (\(spawnError)).")
        }
        lock.lock(); processID = pid; let cancelled = cancellation != nil; lock.unlock()
        onStart(pid)
        if cancelled { terminateGroup(pid) }
        let output = ScriptOutputCapture(limit: outputLimit), errors = ScriptOutputCapture(limit: outputLimit)
        let reads = DispatchGroup()
        for (fd, capture) in [(outFD[0], output), (errFD[0], errors)] {
            reads.enter()
            DispatchQueue.global(qos: .utility).async { capture.readAll(from: fd); reads.leave() }
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR { }
        // A script may exit while its background children still hold stdout open.
        _ = kill(-pid, SIGKILL)
        reads.wait()
        lock.lock(); finished = true; let cause = cancellation; lock.unlock()
        if let cause {
            if cause == .cancelled { throw CancellationError() }
            throw ScriptExecutionFailure("Script timed out. Increase its timeout or shorten the script.")
        }
        let code = status & 0x7F == 0 ? Int((status >> 8) & 0xFF) : 128 + Int(status & 0x7F)
        let result = ScriptExecutionOutput(standardOutput: output.string, standardError: errors.string,
                                           exitCode: code, outputTruncated: output.truncated || errors.truncated)
        guard code == 0 else {
            throw ScriptExecutionFailure("Script exited with status \(code). \(result.standardError.prefix(1000))")
        }
        return result
    }

    private func cancel(_ cause: CancellationCause) {
        lock.lock()
        guard !finished, cancellation == nil else { lock.unlock(); return }
        cancellation = cause; let pid = processID
        lock.unlock()
        if pid > 0 { terminateGroup(pid) }
    }
    private func terminateGroup(_ pid: pid_t) {
        _ = kill(-pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(150)) {
            self.lock.lock(); let stillRunning = !self.finished && self.processID == pid; self.lock.unlock()
            if stillRunning { _ = kill(-pid, SIGKILL) }
        }
    }
}

private final class ScriptOutputCapture: @unchecked Sendable {
    private let limit: Int
    private var bytes = Data()
    private(set) var truncated = false
    init(limit: Int) { self.limit = limit }
    var string: String { String(decoding: bytes, as: UTF8.self) }
    func readAll(from fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return }
            let take = min(count, max(0, limit - bytes.count))
            bytes.append(contentsOf: buffer.prefix(take))
            truncated = truncated || take < count
        }
    }
}
