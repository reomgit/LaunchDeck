// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

struct ProfileStore: Sendable {
    let directory: URL

    init(directory: URL = ProfileStore.defaultDirectory) {
        self.directory = directory
    }

    func load() throws -> Configuration {
        let data = try Data(contentsOf: fileURL)
        struct Header: Decodable { let schemaVersion: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        guard (1...3).contains(version) else { throw CocoaError(.fileReadCorruptFile) }
        var configuration: Configuration
        if version == 1 {
            struct LegacyProfile: Decodable {
                let id: UUID; let name: String; let applicationBundleIdentifier: String?; let bindings: [PadBinding]
            }
            struct Legacy: Decodable {
                let profiles: [LegacyProfile]; let selectedDeviceUniqueID: Int32?
            }
            let legacy = try JSONDecoder().decode(Legacy.self, from: data)
            configuration = Configuration(profiles: legacy.profiles.map { Profile(id: $0.id, name: $0.name, applicationBundleIdentifier: $0.applicationBundleIdentifier, bindings: $0.bindings) }, selectedDeviceUniqueID: legacy.selectedDeviceUniqueID)
        } else { configuration = try JSONDecoder().decode(Configuration.self, from: data) }
        configuration.schemaVersion = Configuration.currentSchemaVersion
        try validate(configuration)
        if version < Configuration.currentSchemaVersion {
            let backup = directory.appendingPathComponent("profiles.v\(version).backup.json")
            if FileManager.default.fileExists(atPath: backup.path) {
                guard try Data(contentsOf: backup) == data else { throw CocoaError(.fileWriteFileExists) }
            } else { try data.write(to: backup, options: [.withoutOverwriting]) }
            try save(configuration)
        }
        return configuration
    }

    func save(_ configuration: Configuration) throws {
        try validate(configuration)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Internal autosaves favor compact encoding; portable exports remain formatted.
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    var fileURL: URL {
        directory.appending(path: "profiles.json")
    }

    static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "LaunchDeck")
    }

    func validate(_ configuration: Configuration) throws {
        func reject() throws { throw CocoaError(.fileReadCorruptFile) }
        guard configuration.schemaVersion == Configuration.currentSchemaVersion, configuration.profiles.filter(\.isGlobal).count == 1,
              Set(configuration.profiles.map(\.id)).count == configuration.profiles.count else { try reject(); return }
        let apps = configuration.profiles.filter { $0.kind == .application }.compactMap(\.applicationBundleIdentifier)
        guard Set(apps).count == apps.count else { try reject(); return }
        if let id = configuration.manuallyActivatedProfileID, !configuration.profiles.contains(where: { $0.id == id }) { try reject() }
        // Validate active effective layouts and every explicitly stored dormant layout.
        // An absent dormant override must not invent dependencies on another dormant layout.
        for inspectStored in [false, true] {
            var global = configuration.profiles.first(where: \.isGlobal)
            if inspectStored { global?.modelOverridesEnabled = true }
            for var profile in configuration.profiles {
                if inspectStored { profile.modelOverridesEnabled = true }
                for model in inspectStored ? profile.storedModels : DeviceModel.allCases {
                    let layout = inspectStored ? profile.storedLayout(for: model) : profile.layout(for: model)
                    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        (profile.kind == .application ? !(profile.applicationBundleIdentifier ?? "").isEmpty : profile.applicationBundleIdentifier == nil),
                        Set(layout.pages.map(\.id)).count == layout.pages.count,
                        Set(layout.folders.map(\.id)).count == layout.folders.count,
                        layout.pages.first?.id == DeckPage.homeID, layout.pages.first?.folderID == nil else { try reject(); return }
                    for page in layout.pages {
                        try page.lighting?.validate()
                        guard Set(page.bindings.map(\.index)).count == page.bindings.count else { try reject(); return }
                        guard page.bindings.allSatisfy({ (0..<model.descriptor.controlCount).contains($0.index) }) else { try reject(); return }
                    }
                    let resolver = ProfileResolver()
                    let pages = resolver.effectivePages(profile: profile, global: global, model: model)
                    let folders = resolver.effectiveFolders(profile: profile, global: global, model: model)
                    let ids = Set(folders.map(\.id))
                    for (order, validIDs) in [(layout.pageOrder, Set(pages.map(\.id))), (layout.folderOrder, ids)] {
                        if let order, (Set(order).count != order.count || !Set(order).isSubset(of: validIDs)) { try reject() }
                    }
                    for folder in folders {
                        var seen: Set<UUID> = [folder.id]; var parent = folder.parentFolderID
                        while let id = parent {
                            guard ids.contains(id), seen.insert(id).inserted else { try reject(); return }
                            parent = folders.first { $0.id == id }?.parentFolderID
                        }
                    }
                    for page in pages {
                        if let id = page.folderID, !ids.contains(id) { try reject() }
                        guard Set(page.bindings.map(\.index)).count == page.bindings.count else { try reject(); return }
                        for binding in page.bindings {
                            guard (0..<model.descriptor.controlCount).contains(binding.index), binding.color.red <= 127, binding.color.green <= 127, binding.color.blue <= 127 else { try reject(); return }
                            if let artwork = binding.artworkID, !Self.validArtworkID(artwork) { try reject() }
                            switch binding.action {
                            case let .macro(steps):
                                guard !steps.isEmpty else { try reject(); return }
                                for step in steps { try validateStep(step) }
                            case let .step(step): try validateStep(step)
                            case let .navigation(.openFolder(id)): if !ids.contains(id) { try reject() }
                            default: break
                            }
                        }
                    }
                }
            }
        }
    }
    static func validArtworkID(_ id: String) -> Bool { UUID(uuidString: id) != nil }
    private func validateStep(_ step: MacroStep) throws {
        switch step {
        case let .delay(milliseconds): guard milliseconds >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        case let .launchApplication(identifier): guard !identifier.isEmpty, !identifier.contains("/") else { throw CocoaError(.fileReadCorruptFile) }
        case let .openWebsite(string): guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw CocoaError(.fileReadCorruptFile) }
        case let .openFile(target), let .openFolder(target):
            guard !target.bookmark.isEmpty, target.displayPath.hasPrefix("/") else { throw CocoaError(.fileReadCorruptFile) }
        case let .text(text): guard text.utf8.count <= 100000 else { throw CocoaError(.fileReadCorruptFile) }
        case let .script(script): try script.validate()
        case let .httpRequest(request): try request.validate()
        case let .extensionAction(invocation):
            guard !invocation.extensionID.isEmpty, !invocation.actionID.isEmpty,
                  invocation.extensionID.count <= 200, invocation.actionID.count <= 200,
                  invocation.parameters.count <= 64,
                  invocation.parameters.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 200 && $0.value.utf8.count <= 32_768 }) else { throw CocoaError(.fileReadCorruptFile) }
        case .shortcut: break
        }
    }
}
