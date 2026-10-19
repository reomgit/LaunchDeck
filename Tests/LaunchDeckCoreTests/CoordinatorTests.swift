// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AppKit
import Testing
@testable import LaunchDeckCore

@MainActor
struct CoordinatorTests {
    private func withCoordinator(_ body: (AppCoordinator, ProfileStore) throws -> Void) throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        try body(coordinator, store)
    }

    @Test("Selecting an editor profile does not activate it; manual activation persists")
    func selectionAndActivation() throws {
        try withCoordinator { coordinator, store in
            coordinator.addManualProfile(name: "Writing")
            let manual = try #require(coordinator.selectedProfile)
            #expect(manual.kind == .manual)
            #expect(coordinator.runtimeProfile?.isGlobal == true)
            coordinator.activateSelectedProfile()
            #expect(coordinator.runtimeProfile?.id == manual.id)
            let persisted = try store.load()
            #expect(persisted.manuallyActivatedProfileID == manual.id)
            let restarted = AppCoordinator(profileStore: store)
            defer { restarted.shutdown() }
            #expect(restarted.runtimeProfile?.id == manual.id)
            coordinator.selectProfile(coordinator.configuration.profiles.first(where: \.isGlobal)?.id)
            #expect(coordinator.runtimeProfile?.id == manual.id)
            coordinator.useAutoProfiles()
            #expect(coordinator.runtimeProfile?.isGlobal == true)
        }
    }

    @Test("Deleting the manually active profile restores Auto mode")
    func deletionRestoresAuto() throws {
        try withCoordinator { coordinator, store in
            coordinator.addManualProfile()
            coordinator.activateSelectedProfile()
            coordinator.removeSelectedProfile()
            #expect(coordinator.configuration.manuallyActivatedProfileID == nil)
            let persisted = try store.load()
            #expect(persisted.manuallyActivatedProfileID == nil)
            #expect(coordinator.runtimeProfile?.isGlobal == true)
        }
    }

    @Test("Editing an inherited label preserves its action and appearance")
    func inheritedEditing() throws {
        try withCoordinator { coordinator, _ in
            coordinator.selectPad(79)
            coordinator.assign(PadBinding(index: 79, label: "Website", color: .green, action: .step(.openWebsite("https://example.com")), symbolName: "globe"), to: 79)
            coordinator.addApplicationProfile(bundleIdentifier: "test.app", name: "App")
            coordinator.selectPad(79)
            coordinator.updateSelectedBinding(label: "Docs")
            #expect(coordinator.selectedProfileBinding(at: 79)?.symbolName == "globe")
            #expect(coordinator.selectedProfileBinding(at: 79)?.action == .step(.openWebsite("https://example.com")))
            coordinator.clearSelectedPad()
            #expect(coordinator.isInherited(at: 79))
            #expect(coordinator.displayedBinding(at: 79)?.label == "Website")
            coordinator.disableSelectedPad()
            #expect(coordinator.displayedBinding(at: 79)?.action == .disabled)
        }
    }

    @Test("Editor page changes do not change the runtime page")
    func editorNavigationIsIndependent() throws {
        try withCoordinator { coordinator, _ in
            coordinator.createPage(name: "Second")
            #expect(coordinator.selectedPage?.name == "Second")
            #expect(coordinator.runtimePage?.id == DeckPage.homeID)
            coordinator.executeNavigation(.nextPage)
            #expect(coordinator.runtimePage?.name == "Second")
            coordinator.selectPage(DeckPage.homeID)
            #expect(coordinator.runtimePage?.name == "Second")
            coordinator.executeNavigation(.home)
            #expect(coordinator.runtimePage?.id == DeckPage.homeID)
        }
    }

    @Test("Deleting a folder removes cross-profile navigation references")
    func deletingGlobalFolder() throws {
        try withCoordinator { coordinator, _ in
            let globalID = try #require(coordinator.selectedProfileID)
            coordinator.createFolder(name: "Tools")
            let folder = try #require(coordinator.editorFolders.first)
            coordinator.selectPage(DeckPage.homeID)
            coordinator.selectPad(0)
            coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id)))
            coordinator.addApplicationProfile(bundleIdentifier: "test.app", name: "App")
            coordinator.selectPad(1)
            coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id)))
            coordinator.selectProfile(globalID)
            coordinator.deleteFolder(folder.id)
            #expect(coordinator.configuration.profiles.allSatisfy { profile in
                profile.pages.allSatisfy { page in
                    page.bindings.allSatisfy { $0.action != .navigation(.openFolder(folder.id)) }
                }
            })
        }
    }

    @Test("Renaming home preserves its first-page position and saves successfully")
    func renameHome() throws {
        try withCoordinator { coordinator, store in
            coordinator.createPage(name: "Second")
            coordinator.renamePage(DeckPage.homeID, name: "Start")
            #expect(coordinator.configuration.profiles[0].pages.first?.id == DeckPage.homeID)
            #expect(coordinator.persistenceError == nil)
            let loaded = try store.load()
            #expect(loaded.profiles[0].pages.first?.name == "Start")
        }
    }

    @Test("Composed artwork is stored and included in a portable profile")
    func composedArtwork() throws {
        try withCoordinator { coordinator, store in
            coordinator.selectPad(0)
            coordinator.updateSelectedBinding(label: "Tools", color: PadColor(red: 127, green: 0, blue: 0))
            coordinator.setSelectedSymbol("star.fill")
            coordinator.composeSelectedArtwork()
            let artworkID = try #require(coordinator.displayedBinding(at: 0)?.artworkID)
            let data = try Data(contentsOf: coordinator.artworkURL(for: artworkID))
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.pixelsWide == 256)
            #expect(bitmap.pixelsHigh == 256)
            var pixel = [Int](repeating: 0, count: 4)
            bitmap.getPixel(&pixel, atX: 0, y: 0)
            #expect(pixel == [255, 0, 0, 255])
            let packages = ProfilePackageStore(directory: store.directory)
            let url = store.directory.appending(path: "Tools.launchdeckprofile")
            try packages.export(profile: #require(coordinator.selectedProfile), global: nil, to: url)
            let imported = try packages.importProfile(from: url)
            #expect(imported.kind == .manual)
            let importedID = try #require(imported.bindings.first?.artworkID)
            #expect(importedID != artworkID)
            #expect(NSBitmapImageRep(data: try Data(contentsOf: packages.artworkURL(for: importedID))) != nil)
        }
    }

    @Test("Inherited page ordering persists without materializing control overrides")
    func inheritedOrdering() throws {
        try withCoordinator { coordinator, store in
            coordinator.createPage(name: "A")
            let a = coordinator.selectedPageID
            coordinator.createPage(name: "B")
            let b = coordinator.selectedPageID
            coordinator.addApplicationProfile(bundleIdentifier: "test.app", name: "App")
            coordinator.movePage(b, by: -1)
            #expect(coordinator.editorPages.map(\.id) == [DeckPage.homeID, b, a])
            #expect(coordinator.selectedProfile?.pages.count == 1)
            #expect(coordinator.persistenceError == nil)
            let restored = try store.load()
            let profile = try #require(restored.profiles.last)
            #expect(profile.pageOrder == [DeckPage.homeID, b, a])
        }
    }

    @Test("Renaming an application page leaves inherited controls live")
    func renameDoesNotMaterializeInheritedBindings() throws {
        try withCoordinator { coordinator, _ in
            let global = try #require(coordinator.selectedProfileID)
            coordinator.selectPad(0)
            coordinator.updateSelectedBinding(label: "Original")
            coordinator.addApplicationProfile(bundleIdentifier: "test.app", name: "App")
            let app = try #require(coordinator.selectedProfileID)
            coordinator.renamePage(DeckPage.homeID, name: "App Home")
            #expect(coordinator.selectedProfile?.bindings.isEmpty == true)
            coordinator.selectProfile(global)
            coordinator.selectPad(0)
            coordinator.updateSelectedBinding(label: "Updated")
            coordinator.selectProfile(app)
            #expect(coordinator.displayedBinding(at: 0)?.label == "Updated")
        }
    }

    @Test("Deleting inherited folders cleans application page ordering")
    func deletedFolderOrdering() throws {
        try withCoordinator { coordinator, store in
            let global = try #require(coordinator.selectedProfileID)
            coordinator.createFolder(name: "Folder")
            let folder = try #require(coordinator.editorFolders.first)
            coordinator.createPage(name: "Page 2", folderID: folder.id)
            let page = coordinator.selectedPageID
            coordinator.addApplicationProfile(bundleIdentifier: "test.app", name: "App")
            coordinator.movePage(page, by: -1)
            coordinator.selectProfile(global)
            coordinator.deleteFolder(folder.id)
            #expect(coordinator.persistenceError == nil)
            #expect(coordinator.configuration.profiles.last?.pageOrder == [DeckPage.homeID])
            #expect(try store.load().profiles.last?.pageOrder == [DeckPage.homeID])
        }
    }

    @Test("Hardware navigation works without keyboard permission and ignores stale connections")
    func hardwareNavigation() throws {
        try withCoordinator { coordinator, _ in
            coordinator.selectPad(64)
            coordinator.updateSelectedBinding(action: .navigation(.nextPage))
            coordinator.createPage(name: "Second")
            let generation = coordinator.midi.connectionGeneration
            coordinator.midi.onPadEvent?(PadEvent(index: 64, phase: .pressed, generation: generation - 1))
            #expect(coordinator.runtimePage?.id == DeckPage.homeID)
            coordinator.midi.onPadEvent?(PadEvent(index: 64, phase: .pressed, generation: generation))
            #expect(coordinator.runtimePage?.name == "Second")
            coordinator.midi.onPadEvent?(PadEvent(index: 64, phase: .released, generation: generation))
        }
    }

    @Test("Save failures are visible while preserving edits in memory")
    func reportsSaveFailure() throws {
        try withCoordinator { coordinator, store in
            try FileManager.default.removeItem(at: store.fileURL)
            try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
            coordinator.addManualProfile(name: "Unsaved")
            #expect(coordinator.selectedProfile?.name == "Unsaved")
            #expect(coordinator.persistenceError != nil)
        }
    }

    @Test("Unreadable configuration is reported and protected from automatic overwrite")
    func corruptStore() throws {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let damaged = Data("broken configuration".utf8)
        try damaged.write(to: store.fileURL)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        #expect(coordinator.persistenceError != nil)
        coordinator.addManualProfile()
        #expect(try Data(contentsOf: store.fileURL) == damaged)
    }
}
