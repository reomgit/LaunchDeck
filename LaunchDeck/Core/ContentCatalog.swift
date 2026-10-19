// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

enum ContentType: String, Codable, CaseIterable, Sendable {
    case profile, iconPack, extensionPackage
    var displayName: String { switch self { case .profile: "Profiles"; case .iconPack: "Icon Packs"; case .extensionPackage: "Extensions" } }
}
struct ContentCatalogEntry: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var type: ContentType
    var name: String
    var author: String
    var license: String
    var description: String
    var supportedApplications: [String] = []
    var supportedDeviceModels: [String] = []
    var supportedServices: [String] = []
    var version: String
    var artifactURL: String
    var size: Int
    var sha256: String
    @discardableResult func verify(_ data: Data) throws -> Bool {
        guard data.count == size else { throw EcosystemError("\(name) download size does not match its catalog entry.") }
        guard ContentCatalog.digest(data) == sha256.lowercased() else { throw EcosystemError("\(name) checksum does not match its catalog entry.") }
        return true
    }
    func validate(allowBundled: Bool = false) throws {
        guard ExtensionRegistry.validID(id), !name.isEmpty, !author.isEmpty, !license.isEmpty, ExtensionRegistry.validVersion(version), (1...50_000_000).contains(size), sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }) else { throw EcosystemError("Invalid catalog metadata for \(name).") }
        guard supportedDeviceModels.allSatisfy({ DeviceModel(rawValue: $0) != nil }), Set(supportedDeviceModels).count == supportedDeviceModels.count else { throw EcosystemError("Unsupported or duplicate device model in catalog entry \(name).") }
        guard let url = URL(string: artifactURL), (allowBundled && url.scheme == "launchdeck-bundled") || ContentCatalog.validRemoteURL(url) else { throw EcosystemError("Catalog artifacts require HTTPS URLs.") }
    }
    func isNewer(than version: String) -> Bool {
        let left = self.version.split(separator: ".").compactMap { Int($0) }
        let right = version.split(separator: ".").compactMap { Int($0) }
        for (a, b) in zip(left, right) { if a != b { return a > b } }
        return false
    }
}
struct ContentCatalog: Codable, Sendable {
    var schemaVersion: Int = 1
    var entries: [ContentCatalogEntry]
    func validate(allowBundled: Bool = false) throws {
        guard schemaVersion == 1, entries.count <= 2_000, Set(entries.map(\.id)).count == entries.count else { throw EcosystemError("Unsupported catalog version or duplicate entries.") }
        for entry in entries { try entry.validate(allowBundled: allowBundled) }
    }
    func filtered(query: String, type: ContentType? = nil, model: String? = nil, application: String? = nil) -> [ContentCatalogEntry] {
        entries.filter { entry in
            (type == nil || entry.type == type) && (model == nil || entry.supportedDeviceModels.isEmpty || entry.supportedDeviceModels.contains(model!)) && (application == nil || entry.supportedApplications.isEmpty || entry.supportedApplications.contains(application!)) && (query.isEmpty || ([entry.name, entry.description, entry.author] + entry.supportedApplications + entry.supportedServices).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func validRemoteURL(_ url: URL) -> Bool {
        guard url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else { return false }
        return url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased()))
    }
}
