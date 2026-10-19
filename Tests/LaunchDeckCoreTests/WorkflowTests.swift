import XCTest
import ImageIO
import CoreGraphics
@testable import LaunchDeckCore

final class WorkflowTests: XCTestCase {
    func testManualIsIndependentAndNavigationBoundaries() throws {
        let binding = PadBinding(index: 0, label: "Global", color: .blue, action: .shortcut(.copy))
        let global = Profile(name: "Global", applicationBundleIdentifier: nil, bindings: [binding])
        let manual = Profile(name: "Manual", kind: .manual)
        let resolver = ProfileResolver()
        XCTAssertNil(resolver.resolve(profiles: [global, manual], bundleIdentifier: nil, revision: 1, profileID: manual.id).binding(at: 0))
        var navigation = DeckNavigation()
        navigation.reset(pages: manual.pages)
        XCTAssertFalse(navigation.perform(.nextPage, pages: manual.pages, folders: []))
    }
    func testLegacyMigrationPreservesOriginalBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data("{\"schemaVersion\":1,\"profiles\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Global\",\"bindings\":[]}] }".utf8)
        let store = ProfileStore(directory: directory)
        try data.write(to: store.fileURL)
        XCTAssertEqual(try store.load().schemaVersion, Configuration.currentSchemaVersion)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("profiles.v1.backup.json")), data)
    }

    func testApplicationOverlayAndExplicitActivation() throws {
        let globalBinding = PadBinding(index: 1, label: "Copy", color: .blue, action: .shortcut(.copy))
        let global = Profile(name: "Global", bindings: [globalBinding])
        let app = Profile(name: "App", applicationBundleIdentifier: "example.app", bindings: [PadBinding(index: 0, label: "Paste", color: .green, action: .shortcut(.paste))])
        let resolver = ProfileResolver()
        XCTAssertEqual(resolver.activeProfile(profiles: [global, app], bundleIdentifier: nil, manuallyActivatedProfileID: app.id)?.id, app.id)
        XCTAssertEqual(resolver.effectivePages(profile: app, global: global)[0].bindings.count, 2)
        XCTAssertNotNil(resolver.resolve(profiles: [global, app], bundleIdentifier: "example.app", revision: 0).binding(at: 1))
    }
    func testFolderHistoryIgnoresPageTurns() {
        let folder = DeckFolder(name: "Tools")
        let second = DeckPage(id: UUID(), name: "Second", folderID: folder.id)
        let pages = [DeckPage(), DeckPage(id: UUID(), name: "First", folderID: folder.id), second]
        var navigation = DeckNavigation()
        XCTAssertTrue(navigation.perform(.openFolder(folder.id), pages: pages, folders: [folder]))
        XCTAssertTrue(navigation.perform(.nextPage, pages: pages, folders: [folder]))
        XCTAssertEqual(navigation.history, [DeckPage.homeID])
        XCTAssertTrue(navigation.perform(.back, pages: pages, folders: [folder]))
        XCTAssertEqual(navigation.pageID, DeckPage.homeID)
        XCTAssertFalse(navigation.perform(.home, pages: pages, folders: [folder]))
        XCTAssertTrue(navigation.history.isEmpty)
    }
    func testInvalidConfigurationAndUnknownVersionAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let id = UUID()
        let cycle = DeckFolder(id: id, name: "Cycle", parentFolderID: id)
        XCTAssertThrowsError(try store.validate(Configuration(profiles: [Profile(name: "Global", folders: [cycle])])))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let unknown = Data("{\"schemaVersion\":99}".utf8)
        try unknown.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), unknown)
    }
    func testPackageRoundTripCreatesIndependentManualAndRejectsInvalidAssets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProfilePackageStore(directory: directory)
        let global = Profile(name: "Global", bindings: [PadBinding(index: 1, label: "Copy", color: .blue, action: .shortcut(.copy))])
        let app = Profile(name: "App", applicationBundleIdentifier: "example.app")
        let url = directory.appendingPathComponent("test.launchdeckprofile")
        try store.export(profile: app, global: global, to: url)
        let imported = try store.importProfile(from: url)
        XCTAssertEqual(imported.kind, .manual)
        XCTAssertNotEqual(imported.id, app.id)
        XCTAssertEqual(imported.bindings.count, 1)
        XCTAssertThrowsError(try store.importArtwork(data: Data("not an image".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.artworkURL(for: UUID().uuidString).path))
    }

    func testImageAssetRoundTripAndCorruptLegacyPreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let packages = ProfilePackageStore(directory: directory)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let png = bytes as Data
        let artwork = try packages.importArtwork(data: png)
        let manual = Profile(name: "Art", bindings: [PadBinding(index: 0, label: "Art", color: .blue, action: .disabled, artworkID: artwork)], kind: .manual)
        let url = directory.appendingPathComponent("art.launchdeckprofile")
        try packages.export(profile: manual, global: nil, to: url)
        let imported = try packages.importProfile(from: url)
        let importedArt = try XCTUnwrap(imported.bindings.first?.artworkID)
        XCTAssertNotEqual(importedArt, artwork)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packages.artworkURL(for: importedArt).path))
        let store = ProfileStore(directory: directory)
        let corrupt = Data("{\"schemaVersion\":1,\"profiles\":[]}".utf8)
        try corrupt.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("profiles.v1.backup.json").path))
    }

    func testInheritedExplicitOrderingAndLongLegacyCompatibleMacro() throws {
        let a = DeckPage(id: UUID(), name: "A")
        let b = DeckPage(id: UUID(), name: "B")
        let f1 = DeckFolder(name: "One")
        let f2 = DeckFolder(name: "Two")
        let global = Profile(name: "Global", pages: [DeckPage(), a, b], folders: [f1, f2])
        var app = Profile(name: "App", applicationBundleIdentifier: "example.app", pages: [DeckPage(), DeckPage(id: a.id, name: "Renamed")])
        let resolver = ProfileResolver()
        XCTAssertEqual(resolver.effectivePages(profile: app, global: global).map(\.id), [DeckPage.homeID, a.id, b.id])
        app.pageOrder = [DeckPage.homeID, b.id, a.id]
        app.folderOrder = [f2.id, f1.id]
        XCTAssertEqual(resolver.effectivePages(profile: app, global: global).map(\.id), app.pageOrder)
        XCTAssertEqual(resolver.effectiveFolders(profile: app, global: global).map(\.id), app.folderOrder)
        app.bindings = [PadBinding(index: 0, label: "Long", color: .blue, action: .macro(Array(repeating: .delay(milliseconds: 60001), count: 257)))]
        XCTAssertNoThrow(try ProfileStore().validate(Configuration(profiles: [global, app])))
    }
    func testMissingFileBookmarkDoesNotInvalidateConfiguration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: url)
        let target = try FileTarget(url: url)
        try FileManager.default.removeItem(at: url)
        let profile = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "File", color: .blue, action: .step(.openFile(target)))])
        XCTAssertNoThrow(try ProfileStore().validate(Configuration(profiles: [profile])))
        XCTAssertEqual(BindingAction.navigation(.nextPage).displayName, "Next Page")
        XCTAssertEqual(MacroStep.text("Hello").displayName, "Type Text")
    }

    func testPackageRejectsUnreferencedAssetsCyclesAndGIF() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let packages = ProfilePackageStore(directory: directory)
        let url = directory.appendingPathComponent("invalid.launchdeckprofile")
        try packages.export(profile: Profile(name: "Manual", kind: .manual), global: nil, to: url)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        manifest["assets"] = [UUID().uuidString: Data("bad".utf8).base64EncodedString()]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        XCTAssertThrowsError(try packages.importProfile(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Artwork").path))
        let cycleID = UUID()
        let cycle = Profile(name: "Cycle", kind: .manual, folders: [DeckFolder(id: cycleID, name: "Cycle", parentFolderID: cycleID)])
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cycle))
        manifest["profile"] = profileObject; manifest["assets"] = [:] as [String: String]
        try JSONSerialization.data(withJSONObject: manifest).write(to: url)
        XCTAssertThrowsError(try packages.importProfile(from: url))
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let gif = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(gif, "com.compuserve.gif" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertThrowsError(try packages.importArtwork(data: gif as Data))
    }
}
