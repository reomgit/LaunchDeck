// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

struct IconPackManifest: Codable, Sendable {
    var schemaVersion: Int = 1
    var id: String
    var name: String
    var version: String
    var author: String
    var license: String
    var images: [String: Data]
}
struct InstalledIcon: Codable, Hashable, Identifiable, Sendable {
    var id: String { artworkID }
    var name: String
    var artworkID: String
}
struct InstalledIconPack: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var version: String
    var author: String
    var license: String
    var icons: [InstalledIcon]
}
@MainActor
final class IconPackStore: ObservableObject {
    @Published private(set) var installedPacks: [InstalledIconPack] = []
    let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("IconPacks/installed.json") }
    var installedIcons: [InstalledIcon] { installedPacks.flatMap(\.icons) }
    init(directory: URL) throws {
        self.directory = directory
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let bytes = try Data(contentsOf: stateURL)
            guard bytes.count <= 5_000_000 else { throw EcosystemError("Installed icon pack metadata is too large.") }
            installedPacks = try JSONDecoder().decode([InstalledIconPack].self, from: bytes)
            guard Set(installedPacks.map(\.id)).count == installedPacks.count, installedPacks.allSatisfy({ ExtensionRegistry.validID($0.id) && $0.icons.allSatisfy { ProfileStore.validArtworkID($0.artworkID) } }) else { throw EcosystemError("Invalid installed icon pack metadata.") }
        }
    }
    func install(from url: URL) throws { try install(data: Data(contentsOf: url)) }
    func install(data: Data) throws {
        guard data.count <= 50_000_000 else { throw EcosystemError("Icon pack exceeds 50 MB.") }
        let manifest = try JSONDecoder().decode(IconPackManifest.self, from: data)
        guard manifest.schemaVersion == 1, ExtensionRegistry.validID(manifest.id), ExtensionRegistry.validVersion(manifest.version), !manifest.name.isEmpty, !manifest.author.isEmpty, !manifest.license.isEmpty, (1...256).contains(manifest.images.count), manifest.images.keys.allSatisfy({ !$0.isEmpty && $0.count <= 100 }) else { throw EcosystemError("Invalid icon pack metadata.") }
        let artwork = ProfilePackageStore(directory: directory)
        var icons: [InstalledIcon] = []
        do {
            for (name, image) in manifest.images.sorted(by: { $0.key < $1.key }) {
                icons.append(InstalledIcon(name: name, artworkID: try artwork.importArtwork(data: image)))
            }
            let pack = InstalledIconPack(id: manifest.id, name: manifest.name, version: manifest.version, author: manifest.author, license: manifest.license, icons: icons)
            var packs = installedPacks.filter { $0.id != pack.id }
            packs.append(pack)
            try persist(packs)
        } catch {
            for icon in icons { try? FileManager.default.removeItem(at: artwork.artworkURL(for: icon.artworkID)) }
            throw error
        }
    }
    func remove(id: String) throws {
        // Keep normalized artwork referenced by user profiles; only remove the library entry.
        try persist(installedPacks.filter { $0.id != id })
    }
    private func persist(_ packs: [InstalledIconPack]) throws {
        let bytes = try JSONEncoder().encode(packs)
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: stateURL, options: .atomic)
        installedPacks = packs
    }
}
