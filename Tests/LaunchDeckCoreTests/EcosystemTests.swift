import XCTest
import ImageIO
import CoreGraphics
@testable import LaunchDeckCore

final class EcosystemTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    @MainActor func testExtensionLifecycleExpansionAndFailedUpdatePreservesPrior() throws {
        let directory = try directory()
        let registry = try ExtensionRegistry(directory: directory)
        let manifest = ExtensionManifest(id: "org.launchdeck.example", name: "Example", version: "1.0.0", author: "LaunchDeck", license: "GPL-3.0-only", supportedApplications: [], supportedServices: ["Example"], allowedHosts: ["example.org"], actions: [ExtensionAction(id: "greet", name: "Greet", parameters: [ExtensionParameter(id: "name", name: "Name", type: .string, required: true)], recipe: [.text("Hello {{name}}")])])
        let package = directory.appendingPathComponent("example.launchdeckextension")
        try JSONEncoder().encode(manifest).write(to: package)
        try registry.install(from: package)
        let invocation = ExtensionInvocation(extensionID: manifest.id, actionID: "greet", parameters: ["name": "World"])
        XCTAssertEqual(try registry.expandSteps([.extensionAction(invocation)]), [.text("Hello World")])
        XCTAssertThrowsError(try registry.expandSteps([.extensionAction(ExtensionInvocation(extensionID: manifest.id, actionID: "greet"))]))
        var malformed = manifest
        malformed.actions[0].recipe = [.extensionAction(invocation)]
        try JSONEncoder().encode(malformed).write(to: package)
        XCTAssertThrowsError(try registry.install(from: package))
        XCTAssertEqual(registry.installedExtensions.first?.manifest.version, "1.0.0")
        XCTAssertEqual(try ExtensionRegistry(directory: directory).expandSteps([.extensionAction(invocation)]), [.text("Hello World")])
        try registry.setEnabled(id: manifest.id, enabled: false)
        XCTAssertThrowsError(try registry.expandSteps([.extensionAction(invocation)]))
        try registry.remove(id: manifest.id)
        XCTAssertThrowsError(try registry.expandSteps([.extensionAction(invocation)]))
    }
    func testHTTPRequestValidationAndSecretsNeverSerialized() throws {
        let action = HTTPRequestAction(url: "https://example.org/api", method: "POST", allowedHosts: ["example.org"], secretHeaders: ["Authorization": "local-token"])
        try action.validate()
        let json = String(decoding: try JSONEncoder().encode(action), as: UTF8.self)
        XCTAssertTrue(json.contains("local-token"))
        XCTAssertFalse(json.contains("token-value"))
        XCTAssertThrowsError(try HTTPRequestAction(url: "https://evil.org/api", allowedHosts: ["example.org"]).validate())
        XCTAssertThrowsError(try HTTPRequestAction(url: "http://example.org/api", allowedHosts: ["example.org"]).validate())
        try HTTPRequestAction(url: "http://127.0.0.1/api", allowedHosts: ["127.0.0.1"]).validate()
    }
    func testCatalogValidationFiltersAndDigest() throws {
        let bytes = Data("artifact".utf8)
        let entry = ContentCatalogEntry(id: "example", type: .extensionPackage, name: "Example", author: "A", license: "MIT", description: "Home actions", supportedApplications: ["org.example.app"], supportedDeviceModels: ["miniMK3"], supportedServices: ["Home Assistant"], version: "1.0.0", artifactURL: "https://example.org/file", size: bytes.count, sha256: ContentCatalog.digest(bytes))
        let catalog = ContentCatalog(entries: [entry])
        try catalog.validate()
        XCTAssertEqual(catalog.filtered(query: "assistant", type: .extensionPackage, model: "miniMK3", application: nil).count, 1)
        XCTAssertEqual(catalog.filtered(query: "", type: .profile, model: nil, application: nil).count, 0)
        XCTAssertTrue(try entry.verify(bytes))
        XCTAssertThrowsError(try entry.verify(Data("different".utf8)))
    }
}

extension EcosystemTests {
    @MainActor func testIconPackCreatesFreshAssetIDsAndMalformedInstallRollsBack() throws {
        let directory = try directory()
        let store = try IconPackStore(directory: directory)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let png = bytes as Data
        let manifest = IconPackManifest(id: "org.launchdeck.icons", name: "Icons", version: "1.0.0", author: "A", license: "MIT", images: ["Star": png])
        try store.install(data: JSONEncoder().encode(manifest))
        let first = try XCTUnwrap(store.installedPacks.first?.icons.first?.artworkID)
        XCTAssertNotNil(UUID(uuidString: first))
        try store.install(data: JSONEncoder().encode(manifest))
        XCTAssertNotEqual(first, store.installedPacks.first?.icons.first?.artworkID)
        var broken = manifest
        broken.images["Broken"] = Data("not an image".utf8)
        let previous = store.installedPacks
        XCTAssertThrowsError(try store.install(data: JSONEncoder().encode(broken)))
        XCTAssertEqual(store.installedPacks, previous)
        XCTAssertEqual(try IconPackStore(directory: directory).installedPacks, previous)
    }
}

extension EcosystemTests {
    @MainActor func testBundledCatalogInstallsAllThreeTypesAndPersistsStatus() async throws {
        let directory = try directory()
        let registry = try ExtensionRegistry(directory: directory)
        let service = try ContentLibraryService(directory: directory, registry: registry)
        XCTAssertEqual(Set(service.entries.map(\.type)), [.profile, .iconPack, .extensionPackage])
        var profiles: [Profile] = []
        for entry in service.entries { try await service.install(entry) { profiles.append($0) } }
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.kind, .manual)
        XCTAssertEqual(registry.installedExtensions.count, 1)
        XCTAssertEqual(service.iconPacks.installedIcons.count, 3)
        let restored = try ContentLibraryService(directory: directory, registry: registry)
        XCTAssertTrue(restored.entries.allSatisfy { restored.installedVersion(for: $0) == $0.version })
    }
}

extension EcosystemTests {
    @MainActor func testRecipeScriptArgumentsStayStructuredAndSecretReferencesCannotBecomeText() throws {
        let directory = try directory()
        let registry = try ExtensionRegistry(directory: directory)
        let script = ScriptAction(source: .inline("printf '%s' \"$1\""), language: .shell, arguments: ["{{value}}"])
        var manifest = ExtensionManifest(id: "org.test.script", name: "Script", version: "1.0.0", author: "A", license: "MIT", actions: [ExtensionAction(id: "run", name: "Run", parameters: [ExtensionParameter(id: "value", name: "Value", type: .string, required: true)], recipe: [.script(script)])])
        try registry.install(data: JSONEncoder().encode(manifest))
        let value = "; rm -rf hypothetical; $(echo hi)"
        let expanded = try registry.expandSteps([.extensionAction(ExtensionInvocation(extensionID: manifest.id, actionID: "run", parameters: ["value": value]))])
        guard case let .script(result) = expanded.first else { return XCTFail("Expected script") }
        XCTAssertEqual(result.arguments, [value])
        XCTAssertEqual(result.source, script.source)
        XCTAssertEqual(result.id, script.id)
        manifest.actions[0].recipe = [.script(ScriptAction(source: .inline("echo {{value}}"), language: .shell))]
        XCTAssertThrowsError(try registry.install(data: JSONEncoder().encode(manifest)))
        manifest.actions[0].parameters[0].type = .secretReference
        manifest.actions[0].recipe = [.text("{{value}}")]
        XCTAssertThrowsError(try registry.install(data: JSONEncoder().encode(manifest)))
    }
    @MainActor func testCheckedInSampleContentIsValidAndPortable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let samples = root.appendingPathComponent("Samples/Ecosystem")
        if ProcessInfo.processInfo.environment["LAUNCHDECK_EXPORT_SAMPLE_CONTENT"] == "1" {
            try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
            var entries: [ContentCatalogEntry] = []
            for artifact in try BundledStarterContent.artifacts(directory: directory()) {
                let suffix: String
                switch artifact.entry.type { case .profile: suffix = "launchdeckprofile"; case .iconPack: suffix = "launchdeckicons"; case .extensionPackage: suffix = "launchdeckextension" }
                let name = artifact.entry.id + "." + suffix
                try artifact.data.write(to: samples.appendingPathComponent(name), options: .atomic)
                var entry = artifact.entry
                entry.artifactURL = "http://127.0.0.1:8765/" + name
                entries.append(entry)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(ContentCatalog(entries: entries)).write(to: samples.appendingPathComponent("catalog.json"), options: .atomic)
        }
        let catalog = try JSONDecoder().decode(ContentCatalog.self, from: Data(contentsOf: samples.appendingPathComponent("catalog.json")))
        try catalog.validate()
        XCTAssertEqual(catalog.entries.count, 3)
        let registry = try ExtensionRegistry(directory: directory())
        let icons = try IconPackStore(directory: directory())
        for entry in catalog.entries {
            let data = try Data(contentsOf: samples.appendingPathComponent(URL(string: entry.artifactURL)!.lastPathComponent))
            try entry.verify(data)
            switch entry.type {
            case .extensionPackage: try registry.install(data: data)
            case .iconPack: try icons.install(data: data)
            case .profile: _ = try ProfilePackageStore(directory: directory()).importProfile(from: samples.appendingPathComponent(URL(string: entry.artifactURL)!.lastPathComponent))
            }
        }
    }
    func testSensitiveHeadersRequireLocalSecretReferences() throws {
        XCTAssertThrowsError(try HTTPRequestAction(url: "https://example.org/api", headers: ["Authorization": "Bearer exportable"], allowedHosts: ["example.org"]).validate())
    }
}

extension EcosystemTests {
    @MainActor func testUnreadableExtensionStateIsPreserved() throws {
        let directory = try directory()
        let state = directory.appendingPathComponent("Extensions/installed.json")
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("invalid extension registry".utf8)
        try corrupt.write(to: state)
        XCTAssertThrowsError(try ExtensionRegistry(directory: directory))
        XCTAssertEqual(try Data(contentsOf: state), corrupt)
    }
    func testCatalogRejectsUnknownDeviceModels() throws {
        let entry = ContentCatalogEntry(id: "unknown-model", type: .profile, name: "Unknown", author: "A", license: "MIT", description: "Test", supportedDeviceModels: ["future-device"], version: "1.0.0", artifactURL: "https://example.org/package", size: 1, sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try ContentCatalog(entries: [entry]).validate())
    }
}

extension EcosystemTests {
    func testIPv6LoopbackHostValidation() throws {
        try HTTPRequestAction(url: "http://[::1]:8123/api/", allowedHosts: ["::1"]).validate()
        XCTAssertThrowsError(try HTTPRequestAction(url: "http://[::1]:8123/api/", allowedHosts: ["::1", "[::1]"]).validate())
    }
}
