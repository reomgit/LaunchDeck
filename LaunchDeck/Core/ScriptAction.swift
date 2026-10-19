// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import Foundation
import Darwin

enum ScriptLanguage: String, Codable, Hashable, Sendable, CaseIterable {
    case shell, appleScript
    var displayName: String { self == .shell ? "Shell Script" : "AppleScript" }
}

enum ScriptSource: Codable, Hashable, Sendable {
    case inline(String)
    case file(FileTarget)
}

struct ScriptAction: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var source: ScriptSource
    var language: ScriptLanguage
    var arguments: [String]
    var timeoutSeconds: Int
    var targetBundleIdentifiers: [String]

    init(id: UUID = UUID(), source: ScriptSource, language: ScriptLanguage, arguments: [String] = [],
         timeoutSeconds: Int = 30, targetBundleIdentifiers: [String] = []) {
        self.id = id; self.source = source; self.language = language; self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds; self.targetBundleIdentifiers = targetBundleIdentifiers
    }
    var displayName: String { "Run " + language.displayName }
    func validate() throws {
        guard (1...3600).contains(timeoutSeconds), arguments.count <= 64,
              arguments.allSatisfy({ $0.utf8.count <= 10_000 && !$0.contains("\0") }),
              targetBundleIdentifiers.count <= 32,
              targetBundleIdentifiers.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\0") }) else {
            throw ScriptExecutionFailure("Invalid script arguments, timeout, or target applications.")
        }
        switch source {
        case let .inline(code):
            guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  code.utf8.count <= 100_000, !code.contains("\0") else {
                throw ScriptExecutionFailure("Enter a script of at most 100 KB.")
            }
        case let .file(target):
            guard !target.bookmark.isEmpty, target.displayPath.hasPrefix("/") else {
                throw ScriptExecutionFailure("Choose a script file.")
            }
        }
    }
}

struct ScriptExecutionFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ScriptExecutionOutput: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int
    let outputTruncated: Bool
}

/// Capture a bounded regular file once; a concurrent replacement cannot expand allocation.
enum ScriptFileReader {
    static func read(_ url: URL, limit: Int = 1_000_000) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ScriptExecutionFailure("Script file could not be read. Reselect it in the inspector.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ScriptExecutionFailure("Choose a regular script file.")
        }
        var data = Data()
        while data.count <= limit {
            guard let chunk = try handle.read(upToCount: min(65536, limit + 1 - data.count)), !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw ScriptExecutionFailure("Script file exceeds the 1 MB review limit.")
    }
}
