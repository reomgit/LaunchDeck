// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

@MainActor
final class ExtensionRegistry: ObservableObject {
    @Published private(set) var installedExtensions: [InstalledExtension] = []
    let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("Extensions/installed.json") }
    init(directory: URL) throws {
        self.directory = directory
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let data = try Data(contentsOf: stateURL)
            guard data.count <= 20_000_000 else { throw EcosystemError("Installed extensions file is too large.") }
            let entries = try JSONDecoder().decode([InstalledExtension].self, from: data)
            guard Set(entries.map(\.id)).count == entries.count else { throw EcosystemError("Duplicate installed extensions.") }
            for entry in entries { try validate(entry.manifest) }
            installedExtensions = entries
        }
    }
    func install(from url: URL) throws { try install(data: Data(contentsOf: url)) }
    func install(data: Data) throws {
        guard data.count <= 5_000_000 else { throw EcosystemError("Extension package exceeds 5 MB.") }
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        try validate(manifest)
        var entries = installedExtensions
        if let index = entries.firstIndex(where: { $0.id == manifest.id }) {
            let old = entries[index].manifest
            for action in old.actions {
                guard let updated = manifest.actions.first(where: { $0.id == action.id }) else { throw EcosystemError("Update removes action \(action.id); use a new extension ID for incompatible updates.") }
                for parameter in action.parameters {
                    guard let next = updated.parameters.first(where: { $0.id == parameter.id }), next.type == parameter.type, parameter.type != .choice || Set(parameter.choices).isSubset(of: Set(next.choices)) else { throw EcosystemError("Update changes parameter \(parameter.id) incompatibly.") }
                }
                guard !updated.parameters.contains(where: { parameter in parameter.required && parameter.defaultValue == nil && !action.parameters.contains(where: { $0.id == parameter.id && $0.required }) }) else { throw EcosystemError("Update adds a required parameter without a default.") }
            }
            entries[index].manifest = manifest
        } else { entries.append(InstalledExtension(manifest: manifest, enabled: true)) }
        try persist(entries)
    }
    func remove(id: String) throws {
        guard installedExtensions.contains(where: { $0.id == id }) else { throw EcosystemError("Extension \(id) is not installed.") }
        try persist(installedExtensions.filter { $0.id != id })
    }
    func setEnabled(id: String, enabled: Bool) throws {
        var entries = installedExtensions
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw EcosystemError("Extension \(id) is not installed.") }
        entries[index].enabled = enabled; try persist(entries)
    }
    func expandSteps(_ steps: [MacroStep]) throws -> [MacroStep] {
        var expanded: [MacroStep] = []
        for step in steps {
            if case let .extensionAction(invocation) = step {
                guard let installed = installedExtensions.first(where: { $0.id == invocation.extensionID }) else { throw EcosystemError("Install extension \(invocation.extensionID) to use this action.") }
                guard installed.enabled else { throw EcosystemError("Enable extension \(installed.manifest.name) to use this action.") }
                guard let action = installed.manifest.actions.first(where: { $0.id == invocation.actionID }) else { throw EcosystemError("Action \(invocation.actionID) is unavailable in \(installed.manifest.name).") }
                let values = try parameterValues(invocation.parameters, action: action)
                expanded += try action.recipe.map { try substitute($0, values: values, action: action, hosts: installed.manifest.allowedHosts) }
            } else { expanded.append(step) }
            guard expanded.count <= 512 else { throw EcosystemError("Expanded sequence exceeds 512 steps.") }
        }
        return expanded
    }
    func validate(_ manifest: ExtensionManifest) throws {
        guard manifest.schemaVersion == 1, Self.validID(manifest.id), !manifest.name.isEmpty, Self.validVersion(manifest.version), !manifest.author.isEmpty, !manifest.license.isEmpty, (1...64).contains(manifest.actions.count), Set(manifest.actions.map(\.id)).count == manifest.actions.count, manifest.allowedHosts.allSatisfy(HTTPRequestAction.validHost), Set(manifest.allowedHosts).count == manifest.allowedHosts.count else { throw EcosystemError("Invalid extension metadata, hosts, or duplicate action IDs.") }
        for action in manifest.actions {
            guard Self.validID(action.id), !action.name.isEmpty, action.parameters.count <= 32, Set(action.parameters.map(\.id)).count == action.parameters.count, (1...128).contains(action.recipe.count) else { throw EcosystemError("Invalid action \(action.id).") }
            for parameter in action.parameters {
                guard Self.validID(parameter.id), !parameter.name.isEmpty, parameter.type != .choice || (!parameter.choices.isEmpty && Set(parameter.choices).count == parameter.choices.count) else { throw EcosystemError("Invalid parameter \(parameter.id).") }
                if let value = parameter.defaultValue { try parameter.validate(value: value) }
            }
            var sample: [String: String] = [:]
            for parameter in action.parameters {
                sample[parameter.id] = parameter.defaultValue ?? sampleValue(parameter, hosts: manifest.allowedHosts)
            }
            for step in action.recipe { _ = try substitute(step, values: sample, action: action, hosts: manifest.allowedHosts) }
        }
    }
    private func persist(_ entries: [InstalledExtension]) throws {
        let bytes = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: stateURL, options: .atomic)
        installedExtensions = entries.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }
    private func parameterValues(_ input: [String: String], action: ExtensionAction) throws -> [String: String] {
        guard Set(input.keys).isSubset(of: Set(action.parameters.map(\.id))) else { throw EcosystemError("Unknown parameters for \(action.name).") }
        var values = input
        for parameter in action.parameters {
            let value = input[parameter.id] ?? parameter.defaultValue ?? ""
            guard !parameter.required || !value.isEmpty else { throw EcosystemError("Enter \(parameter.name).") }
            if !value.isEmpty { try parameter.validate(value: value) }
            values[parameter.id] = value
        }
        return values
    }
    private func substitute(_ step: MacroStep, values: [String: String], action: ExtensionAction, hosts: [String]) throws -> MacroStep {
        func replace(_ text: String, allowSecrets: Bool = false, json: Bool = false) throws -> String {
            let regex = try NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var result = text
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 1), in: text), let full = Range(match.range, in: text), let parameter = action.parameters.first(where: { $0.id == String(text[range]) }), let value = values[parameter.id] else { throw EcosystemError("Recipe references an unknown parameter.") }
                guard allowSecrets || parameter.type != .secretReference else { throw EcosystemError("Secret references may only appear in HTTP secretHeaders.") }
                let replacement: String
                if json {
                    let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
                    replacement = String(encoded.dropFirst().dropLast())
                } else { replacement = value }
                result.replaceSubrange(full, with: replacement)
            }
            // Reject malformed template syntax rather than silently dropping substitutions.
            guard !result.contains("{{"), !result.contains("}}") else { throw EcosystemError("Malformed recipe parameter template.") }
            return result
        }
        switch step {
        case .extensionAction: throw EcosystemError("Extension recipes cannot invoke other extensions.")
        case let .text(text):
            let value = try replace(text); guard value.utf8.count <= 100_000 else { throw EcosystemError("Recipe text is too long.") }; return .text(value)
        case let .openWebsite(text):
            let value = try replace(text); guard let url = URL(string: value), ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { throw EcosystemError("Recipe website is invalid.") }; return .openWebsite(value)
        case let .launchApplication(text):
            let value = try replace(text); guard !value.isEmpty, !value.contains("/") else { throw EcosystemError("Recipe application identifier is invalid.") }; return .launchApplication(bundleIdentifier: value)
        case let .delay(milliseconds): guard (0...300_000).contains(milliseconds) else { throw EcosystemError("Recipe delay must be between 0 and 300000 ms.") }; return step
        case let .openFile(target), let .openFolder(target): guard !target.bookmark.isEmpty, target.displayPath.hasPrefix("/") else { throw EcosystemError("Recipe file bookmark is invalid.") }; return step
        case .shortcut: return step
        case var .httpRequest(request):
            guard Set(request.allowedHosts.map { $0.lowercased() }).isSubset(of: Set(hosts.map { $0.lowercased() })) else { throw EcosystemError("HTTP recipe uses hosts not declared by the extension.") }
            request.url = try replace(request.url)
            request.headers = try request.headers.mapValues { try replace($0) }
            request.secretHeaders = try request.secretHeaders.mapValues { text in
                let value = try replace(text, allowSecrets: true)
                // Secret references are keys, never credential strings supplied in a package.
                return value
            }
            request.body = try request.body.map { try replace($0, json: true) }
            try request.validate(); return .httpRequest(request)
        case var .script(script):
            switch script.source {
            case let .inline(source): guard !source.contains("{{"), !source.contains("}}") else { throw EcosystemError("Script parameters belong in structured arguments, never script source.") }
            case .file: break
            }
            script.arguments = try script.arguments.map { try replace($0) }
            try script.validate(); return .script(script)
        }
    }
    nonisolated static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
    }
    nonisolated static func validVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { Int($0).map { $0 >= 0 } ?? false }
    }
    private func sampleValue(_ parameter: ExtensionParameter, hosts: [String]) -> String {
        switch parameter.type {
        case .string: "sample"
        case .choice: parameter.choices.first ?? ""
        case .boolean: "true"
        case .number: "1"
        case .url: "https://\(hosts.first ?? "example.org")"
        case .secretReference: "local-secret"
        }
    }
}
