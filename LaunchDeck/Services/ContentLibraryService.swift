// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import CoreGraphics
import ImageIO

struct InstalledContent: Codable, Hashable, Sendable {
    var id: String
    var type: ContentType
    var version: String
}
@MainActor
final class ContentLibraryService: ObservableObject {
    @Published private(set) var entries: [ContentCatalogEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var installedContent: [InstalledContent] = []
    @Published private(set) var catalogURL = ""
    let directory: URL
    let registry: ExtensionRegistry
    let iconPacks: IconPackStore
    private var stateURL: URL { directory.appendingPathComponent("ContentLibrary/installed.json") }
    private var settingsURL: URL { directory.appendingPathComponent("ContentLibrary/catalog.json") }
    private var bundledArtifacts: [String: Data] = [:]
    init(directory: URL, registry: ExtensionRegistry) throws {
        self.directory = directory; self.registry = registry
        iconPacks = try IconPackStore(directory: directory)
        if FileManager.default.fileExists(atPath: stateURL.path) {
            installedContent = try JSONDecoder().decode([InstalledContent].self, from: Data(contentsOf: stateURL))
        }
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            catalogURL = try JSONDecoder().decode(String.self, from: Data(contentsOf: settingsURL))
        }
        try useBundledCatalog()
    }
    func useBundledCatalog() throws {
        let artifacts = try BundledStarterContent.artifacts(directory: directory)
        bundledArtifacts = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.entry.artifactURL, $0.data) })
        entries = artifacts.map(\.entry); errorMessage = nil
    }
    func fetchCatalog(from url: URL) async throws {
        guard !isLoading else { throw EcosystemError("A content operation is already running.") }
        guard ContentCatalog.validRemoteURL(url) else { throw EcosystemError("Enter an HTTPS catalog URL (loopback HTTP is supported for local testing).") }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await BoundedHTTPClient.download(URLRequest(url: url, timeoutInterval: 30), maxBytes: 2_000_000)
            let catalog = try JSONDecoder().decode(ContentCatalog.self, from: data)
            try catalog.validate()
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(url.absoluteString).write(to: settingsURL, options: .atomic)
            entries = catalog.entries; catalogURL = url.absoluteString
        } catch { errorMessage = error.localizedDescription; throw error }
    }
    func installedVersion(for entry: ContentCatalogEntry) -> String? {
        switch entry.type {
        case .extensionPackage: registry.installedExtensions.first { $0.id == entry.id }?.manifest.version
        case .iconPack: iconPacks.installedPacks.first { $0.id == entry.id }?.version
        case .profile: installedContent.first { $0.id == entry.id && $0.type == entry.type }?.version
        }
    }
    func hasUpdate(_ entry: ContentCatalogEntry) -> Bool { installedVersion(for: entry).map { entry.isNewer(than: $0) } ?? false }
    func install(_ entry: ContentCatalogEntry, importProfile: (Profile) throws -> Void) async throws {
        guard !isLoading else { throw EcosystemError("A content operation is already running.") }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try entry.validate(allowBundled: true)
            let data: Data
            if let bundled = bundledArtifacts[entry.artifactURL] { data = bundled }
            else {
                guard let url = URL(string: entry.artifactURL), ContentCatalog.validRemoteURL(url) else { throw EcosystemError("Unknown bundled artifact or invalid download URL.") }
                data = try await BoundedHTTPClient.download(URLRequest(url: url, timeoutInterval: 60), maxBytes: entry.size)
            }
            try entry.verify(data)
            try Task.checkCancellation()
            switch entry.type {
            case .extensionPackage:
                let package = try JSONDecoder().decode(ExtensionManifest.self, from: data)
                guard package.id == entry.id, package.version == entry.version else { throw EcosystemError("Extension ID/version differs from the catalog entry.") }
                try registry.install(data: data)
            case .iconPack:
                let package = try JSONDecoder().decode(IconPackManifest.self, from: data)
                guard package.id == entry.id, package.version == entry.version else { throw EcosystemError("Icon pack ID/version differs from the catalog entry.") }
                try iconPacks.install(data: data)
            case .profile:
                let staging = directory.appendingPathComponent("ContentLibrary/\(UUID().uuidString).launchdeckprofile")
                try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: staging, options: .atomic)
                defer { try? FileManager.default.removeItem(at: staging) }
                let profile = try ProfilePackageStore(directory: directory).importProfile(from: staging)
                try importProfile(profile)
            }
            var installed = installedContent.filter { $0.id != entry.id || $0.type != entry.type }
            installed.append(InstalledContent(id: entry.id, type: entry.type, version: entry.version))
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(installed).write(to: stateURL, options: .atomic)
            installedContent = installed
        } catch { errorMessage = error.localizedDescription; throw error }
    }
}

struct BundledContentArtifact {
    var entry: ContentCatalogEntry
    var data: Data
}
/// Actual embedded starter packages, available without any network or public marketplace.
struct BundledStarterContent {
    @MainActor static func artifacts(directory: URL) throws -> [BundledContentArtifact] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let extensionManifest = ExtensionManifest(id: "org.launchdeck.home-assistant", name: "Home Assistant", version: "1.0.0", author: "LaunchDeck", license: "GPL-3.0-only", supportedServices: ["Home Assistant REST API"], allowedHosts: ["localhost", "127.0.0.1"], actions: [
            ExtensionAction(id: "check-api", name: "Check API", parameters: [
                ExtensionParameter(id: "baseURL", name: "Server URL", type: .url, required: true, defaultValue: "http://localhost:8123"),
                ExtensionParameter(id: "token", name: "Authorization secret reference", type: .secretReference, required: true, defaultValue: "home-assistant-authorization")
            ], recipe: [.httpRequest(HTTPRequestAction(url: "{{baseURL}}/api/", allowedHosts: ["localhost", "127.0.0.1"], secretHeaders: ["Authorization": "{{token}}"]))]),
            ExtensionAction(id: "toggle-light", name: "Toggle Light", parameters: [
                ExtensionParameter(id: "baseURL", name: "Server URL", type: .url, required: true, defaultValue: "http://localhost:8123"),
                ExtensionParameter(id: "entity", name: "Light entity ID", type: .string, required: true, defaultValue: "light.office"),
                ExtensionParameter(id: "token", name: "Authorization secret reference", type: .secretReference, required: true, defaultValue: "home-assistant-authorization")
            ], recipe: [.httpRequest(HTTPRequestAction(url: "{{baseURL}}/api/services/light/toggle", method: "POST", headers: ["Content-Type": "application/json"], body: "{\"entity_id\":\"{{entity}}\"}", allowedHosts: ["localhost", "127.0.0.1"], secretHeaders: ["Authorization": "{{token}}"]))])
        ], symbolName: "house.fill")
        let icons = IconPackManifest(id: "org.launchdeck.starter-icons", name: "Starter Icons", version: "1.0.0", author: "LaunchDeck", license: "GPL-3.0-only", images: ["Home": try iconPNG(shape: 0), "Play": try iconPNG(shape: 1), "Folder": try iconPNG(shape: 2)])
        let profile = Profile(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Desktop Starter", bindings: [PadBinding(index: 0, label: "Copy", color: .blue, action: .shortcut(.copy), symbolName: "doc.on.doc"), PadBinding(index: 1, label: "Paste", color: .green, action: .shortcut(.paste), symbolName: "doc.on.clipboard"), PadBinding(index: 2, label: "Home Assistant Docs", color: .orange, action: .step(.openWebsite("https://developers.home-assistant.io/docs/api/rest/")), symbolName: "house")], kind: .manual)
        let scratch = directory.appendingPathComponent("ContentLibrary/starter-\(UUID().uuidString).launchdeckprofile")
        try FileManager.default.createDirectory(at: scratch.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try ProfilePackageStore(directory: directory).export(profile: profile, global: nil, to: scratch)
        let profileData = try Data(contentsOf: scratch)
        func artifact(id: String, type: ContentType, name: String, description: String, bytes: Data, services: [String] = []) -> BundledContentArtifact {
            BundledContentArtifact(entry: ContentCatalogEntry(id: id, type: type, name: name, author: "LaunchDeck", license: "GPL-3.0-only", description: description, supportedDeviceModels: type == .profile ? ["miniMK3"] : [], supportedServices: services, version: "1.0.0", artifactURL: "launchdeck-bundled://starter/\(id)", size: bytes.count, sha256: ContentCatalog.digest(bytes)), data: bytes)
        }
        return [artifact(id: "org.launchdeck.desktop-starter", type: .profile, name: "Desktop Starter", description: "Copy, paste, and integration documentation. Imported as an independent profile.", bytes: profileData), artifact(id: icons.id, type: .iconPack, name: icons.name, description: "Home, play, and folder symbols as portable PNG artwork.", bytes: try encoder.encode(icons)), artifact(id: extensionManifest.id, type: .extensionPackage, name: extensionManifest.name, description: "Check a local Home Assistant API or toggle a light. Configure Authorization in Keychain before use.", bytes: try encoder.encode(extensionManifest), services: ["Home Assistant"])]
    }
    private static func iconPNG(shape: Int) throws -> Data {
        guard let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EcosystemError("Could not create starter artwork.") }
        context.setFillColor(CGColor(red: 0.10, green: 0.24, blue: 0.36, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 128, height: 128), cornerWidth: 24, cornerHeight: 24, transform: nil)); context.fillPath()
        context.setFillColor(CGColor(red: 0.68, green: 0.94, blue: 0.82, alpha: 1))
        switch shape {
        case 0:
            context.move(to: CGPoint(x: 24, y: 64)); context.addLine(to: CGPoint(x: 64, y: 104)); context.addLine(to: CGPoint(x: 104, y: 64)); context.closePath(); context.fillPath()
            context.fill(CGRect(x: 34, y: 25, width: 60, height: 45))
            context.setFillColor(CGColor(red: 0.10, green: 0.24, blue: 0.36, alpha: 1)); context.fill(CGRect(x: 56, y: 25, width: 16, height: 28))
        case 1:
            context.move(to: CGPoint(x: 45, y: 28)); context.addLine(to: CGPoint(x: 99, y: 64)); context.addLine(to: CGPoint(x: 45, y: 100)); context.closePath(); context.fillPath()
        default:
            context.fill(CGRect(x: 22, y: 30, width: 84, height: 60)); context.fill(CGRect(x: 22, y: 86, width: 34, height: 14))
        }
        let data = NSMutableData()
        guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw EcosystemError("Could not encode starter artwork.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EcosystemError("Could not encode starter artwork.") }
        return data as Data
    }

}
