// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ImageIO

struct ProfilePackageStore: Sendable {
    let directory: URL
    private struct Manifest: Codable {
        let schemaVersion: Int
        let configurationSchemaVersion: Int?
        let deviceModels: [DeviceModel]?
        let profile: Profile
        let assets: [String: Data]
    }
    func artworkURL(for id: String) -> URL { directory.appendingPathComponent("Artwork").appendingPathComponent(id + ".png") }
    func importArtwork(from url: URL) throws -> String {
        try importArtwork(data: Data(contentsOf: url))
    }
    func importArtwork(data: Data, fileExtension: String = "png") throws -> String {
        let normalized = try imageData(data)
        let id = UUID().uuidString
        try FileManager.default.createDirectory(at: artworkURL(for: id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: artworkURL(for: id), options: .atomic)
        return id
    }
    func export(profile: Profile, global: Profile?, to url: URL) throws {
        let manual = ConfigurationOperations.materialize(profile: profile, global: global)
        try validate(manual)
        var assets: [String: Data] = [:]
        for id in Set(manual.storedModels.flatMap { manual.storedLayout(for: $0).pages }.flatMap(\.bindings).compactMap(\.artworkID)) {
            assets[id] = try imageData(Data(contentsOf: artworkURL(for: id)))
        }
        let manifest = Manifest(schemaVersion: 2, configurationSchemaVersion: 3, deviceModels: manual.storedModels, profile: manual, assets: assets)
        try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
    }
    func importProfile(from url: URL) throws -> Profile {
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard (1...2).contains(manifest.schemaVersion), manifest.profile.kind == .manual else { throw CocoaError(.fileReadCorruptFile) }
        if manifest.schemaVersion == 2 {
            guard manifest.configurationSchemaVersion == 3, let models = manifest.deviceModels, Set(models) == Set(manifest.profile.storedModels), Set(models).count == models.count else { throw CocoaError(.fileReadCorruptFile) }
        }
        try validate(manifest.profile)
        let references = Set(manifest.profile.storedModels.flatMap { manifest.profile.storedLayout(for: $0).pages }.flatMap(\.bindings).compactMap(\.artworkID))
        guard references == Set(manifest.assets.keys) else { throw CocoaError(.fileReadCorruptFile) }
        var images: [String: Data] = [:]
        var replacementIDs: [String: String] = [:]
        for (id, asset) in manifest.assets {
            guard ProfileStore.validArtworkID(id) else { throw CocoaError(.fileReadCorruptFile) }
            let newID = UUID().uuidString
            replacementIDs[id] = newID; images[newID] = try imageData(asset)
        }
        var profile = ConfigurationOperations.materialize(profile: manifest.profile, global: nil)
        var importedScriptIDs: [UUID: UUID] = [:]
        func freshStep(_ step: MacroStep) -> MacroStep {
            guard case var .script(script) = step else { return step }
            let replacement = importedScriptIDs[script.id] ?? UUID()
            importedScriptIDs[script.id] = replacement
            script.id = replacement
            return .script(script)
        }
        for model in DeviceModel.allCases {
            var layout = profile.storedLayout(for: model)
            for page in layout.pages.indices {
                for binding in layout.pages[page].bindings.indices {
                    if let id = layout.pages[page].bindings[binding].artworkID { layout.pages[page].bindings[binding].artworkID = replacementIDs[id] }
                    switch layout.pages[page].bindings[binding].action {
                    case let .step(step): layout.pages[page].bindings[binding].action = .step(freshStep(step))
                    case let .macro(steps): layout.pages[page].bindings[binding].action = .macro(steps.map(freshStep))
                    default: break
                    }
                }
            }
            profile.setLayout(layout, for: model)
        }
        let assetDirectory = directory.appendingPathComponent("Artwork")
        try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
        var written: [URL] = []
        do {
            for (id, bytes) in images {
                let target = artworkURL(for: id)
                try bytes.write(to: target, options: [.withoutOverwriting]); written.append(target)
            }
        } catch {
            for target in written { try? FileManager.default.removeItem(at: target) }
            throw error
        }
        return profile
    }
    private func validate(_ profile: Profile) throws {
        try ProfileStore(directory: directory).validate(Configuration(profiles: [Profile(name: "Global"), profile]))
    }
    private func imageData(_ data: Data) throws -> Data {
        guard data.count <= 20_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source), ["public.png", "public.jpeg"].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return result as Data
    }
}
