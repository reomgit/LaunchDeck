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
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        try validate(configuration)
        return configuration
    }

    func save(_ configuration: Configuration) throws {
        try validate(configuration)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }

    var fileURL: URL {
        directory.appending(path: "profiles.json")
    }

    static var defaultDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appending(path: "LaunchDeck")
    }

    private func validate(_ configuration: Configuration) throws {
        guard configuration.schemaVersion == Configuration.currentSchemaVersion,
              configuration.profiles.filter(\.isGlobal).count == 1,
              Set(configuration.profiles.map(\.id)).count == configuration.profiles.count else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let applicationIdentifiers = configuration.profiles.compactMap(\.applicationBundleIdentifier)
        guard Set(applicationIdentifiers).count == applicationIdentifiers.count else {
            throw CocoaError(.fileReadCorruptFile)
        }

        for profile in configuration.profiles {
            let indexes = profile.bindings.map(\.index)
            guard Set(indexes).count == indexes.count,
                  indexes.allSatisfy({ (0..<64).contains($0) }),
                  profile.bindings.allSatisfy({ binding in
                      binding.color.red <= 127 && binding.color.green <= 127 && binding.color.blue <= 127
                  }) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            for binding in profile.bindings {
                if case let .macro(steps) = binding.action,
                   (steps.isEmpty || steps.contains { if case let .delay(milliseconds) = $0 { return milliseconds < 0 }; return false }) {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
        }
    }
}
