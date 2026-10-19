// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
import CryptoKit
import Foundation
import Observation

/// Machine-local consent is tied to complete script content, not a portable ID.
@MainActor @Observable
final class ScriptApprovalStore {
    private(set) var errorMessage: String?
    private var approvals: [String: String] = [:]
    private let fileURL: URL
    private var canSave = true

    init(directory: URL = ProfileStore.defaultDirectory) {
        fileURL = directory.appending(path: "script-approvals.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do { approvals = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fileURL)) }
        catch {
            canSave = false
            errorMessage = "Could not read script approvals. Restore script-approvals.json or remove it to require enabling scripts again."
        }
    }
    func isEnabled(_ script: ScriptAction, fileContents: Data? = nil) -> Bool {
        guard let hash = try? fingerprint(script, fileContents: fileContents) else { return false }
        return approvals[script.id.uuidString] == hash || approvals[script.id.uuidString + ":" + hash] == hash
    }
    func setEnabled(_ script: ScriptAction, enabled: Bool) throws {
        guard canSave else { throw ScriptExecutionFailure(errorMessage ?? "Script approvals could not be read.") }
        try script.validate()
        let hash = try fingerprint(script)
        var updated = approvals
        updated[script.id.uuidString + ":" + hash] = enabled ? hash : nil
        if updated[script.id.uuidString] == hash { updated[script.id.uuidString] = nil }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        approvals = updated
    }
    private func fingerprint(_ script: ScriptAction, fileContents: Data? = nil) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(script)
        if let fileContents { data.append(fileContents) }
        else if case let .file(target) = script.source {
            let url = try target.resolvedURL()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_000_000 else {
                throw ScriptExecutionFailure("Script file exceeds the 1 MB review limit.")
            }
            data.append(try ScriptFileReader.read(url))
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
