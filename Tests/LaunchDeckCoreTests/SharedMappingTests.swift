import Foundation
import Testing
@testable import LaunchDeckCore

struct SharedMappingTests {
    @Test func rawSharedControlsOutsideMiniRangeAreRejectedBeforeProjection() {
        let profile = Profile(name: "Global", bindings: [PadBinding(index: 80, label: "Invalid base control", color: .green, action: .shortcut(.copy))])
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [profile])) }
    }

    @Test @MainActor func modelSpecificDeletionPreservesDependentSharedApplicationMappings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        let globalID = try #require(coordinator.selectedProfileID)
        coordinator.createFolder(name: "Shared Tools")
        let folder = try #require(coordinator.editorFolders.first)
        coordinator.addApplicationProfile(bundleIdentifier: "example.app", name: "Shared App")
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id)))
        coordinator.selectProfile(globalID)
        coordinator.setModelOverridesEnabled(true)
        coordinator.selectEditorModel(.proMK3)
        let before = coordinator.configuration
        coordinator.deleteFolder(folder.id)
        #expect(coordinator.configuration == before)
        #expect(coordinator.persistenceError == nil)
        #expect(coordinator.feedbackMessage?.contains("preserved") == true)
        #expect(try store.load() == before)
    }

    @Test func dormantGlobalLayoutDoesNotInvalidateAnActiveSharedApplication() throws {
        let folder = DeckFolder(name: "Shared Folder")
        var global = Profile(name: "Global", pages: [DeckPage(), DeckPage(id: UUID(), name: "Tools", folderID: folder.id)], folders: [folder])
        global.setLayout(DeckModelLayout(), for: .proMK3)
        let app = Profile(name: "App", applicationBundleIdentifier: "example.shared", bindings: [PadBinding(index: 0, label: "Tools", color: .green, action: .navigation(.openFolder(folder.id)))])
        try ProfileStore().validate(Configuration(profiles: [global, app]))
        #expect(ProfileResolver().effectiveFolders(profile: app, global: global, model: .proMK3).first?.id == folder.id)
    }

    @Test @MainActor func deletingSharedFolderCleansDormantApplicationOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        let globalID = try #require(coordinator.selectedProfileID)
        coordinator.createFolder(name: "Shared Tools")
        let folder = try #require(coordinator.editorFolders.first)
        coordinator.addApplicationProfile(bundleIdentifier: "example.app", name: "App")
        let appID = try #require(coordinator.selectedProfileID)
        coordinator.setModelOverridesEnabled(true)
        coordinator.selectEditorModel(.proMK3)
        coordinator.selectPage(DeckPage.homeID)
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id)))
        coordinator.setModelOverridesEnabled(false)
        coordinator.selectProfile(globalID)
        coordinator.deleteFolder(folder.id)
        #expect(coordinator.persistenceError == nil)
        let loaded = try store.load()
        let app = try #require(loaded.profiles.first { $0.id == appID })
        #expect(!app.storedLayout(for: .proMK3).pages.flatMap(\.bindings).contains { $0.action == .navigation(.openFolder(folder.id)) })
    }

    @Test func legacyOverridesArePreservedWhileSharedMappingsAreDefault() throws {
        var original = Profile(name: "Global", bindings: [PadBinding(index: 0, label: "Shared", color: .green, action: .shortcut(.copy))])
        original.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 0, label: "Old Pro", color: .blue, action: .shortcut(.paste))])]), for: .proMK3)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "modelOverridesEnabled")
        var loaded = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!loaded.modelOverridesEnabled)
        #expect(loaded.layout(for: .proMK3).pages[0].bindings[0].label == "Shared")
        loaded.modelOverridesEnabled = true
        #expect(loaded.layout(for: .proMK3).pages[0].bindings[0].label == "Old Pro")
        loaded.modelOverridesEnabled = false
        #expect(loaded.storedLayout(for: .proMK3).pages[0].bindings[0].label == "Old Pro")
    }

    @Test func dormantOverridesSurvivePortableProfileRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProfilePackageStore(directory: directory)
        var profile = Profile(name: "Shared", bindings: [PadBinding(index: 0, label: "Common", color: .green, action: .shortcut(.copy))], kind: .manual)
        profile.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [PadBinding(index: 104, label: "Saved Shift", color: .blue, action: .shortcut(.paste))])]), for: .proMK3)
        let url = directory.appendingPathComponent("saved.launchdeckprofile")
        try store.export(profile: profile, global: nil, to: url)
        let imported = try store.importProfile(from: url)
        #expect(!imported.modelOverridesEnabled)
        #expect(imported.layout(for: .proMK3).pages[0].bindings[0].label == "Common")
        #expect(imported.storedLayout(for: .proMK3).pages[0].bindings[0].label == "Saved Shift")
    }

    @Test @MainActor func modelOverrideUnlockAndRelockPreserveBothLayouts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(label: "Common")
        coordinator.selectEditorModel(.proMK3)
        coordinator.selectPad(104)
        coordinator.updateSelectedBinding(label: "Blocked")
        #expect(coordinator.displayedBinding(at: 104) == nil)
        coordinator.setModelOverridesEnabled(true)
        coordinator.selectPad(104)
        coordinator.updateSelectedBinding(label: "Shift")
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(label: "Pro")
        coordinator.setModelOverridesEnabled(false)
        #expect(coordinator.displayedBinding(at: 0)?.label == "Common")
        #expect(coordinator.displayedBinding(at: 104) == nil)
        coordinator.setModelOverridesEnabled(true)
        #expect(coordinator.displayedBinding(at: 0)?.label == "Pro")
        #expect(coordinator.displayedBinding(at: 104)?.label == "Shift")
        #expect(try store.load() == coordinator.configuration)
    }

    @Test @MainActor func disabledAssignmentsStayUnlitAndCannotRunOnCompanion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(color: .green, action: .disabled)
        let snapshot = coordinator.companionSnapshot()
        #expect(snapshot.controls[0].color == "#000000")
        #expect(!snapshot.controls[0].enabled)
        #expect(!coordinator.isPaused)
        coordinator.isPaused = true
        #expect(coordinator.statusText == "Paused")
        coordinator.isPaused = false
        #expect(coordinator.statusText != "Paused")
    }

    @Test func switchingModelsRetainsSharedGridAndOuterAssignments() {
        let profile = Profile(name: "Global", bindings: [
            PadBinding(index: 0, label: "Open App", color: .green, action: .shortcut(.copy)),
            PadBinding(index: 79, label: "Next", color: .blue, action: .navigation(.nextPage))
        ])
        for model in DeviceModel.allCases {
            let resolved = ProfileResolver().resolve(profiles: [profile], bundleIdentifier: nil, revision: 1, model: model)
            #expect(resolved.binding(at: 0)?.label == "Open App")
            if model != .virtual { #expect(resolved.binding(at: 79)?.label == "Next") }
            #expect(resolved.binding(at: 104) == nil)
        }
    }

    @Test @MainActor func editingSharedVirtualGridPreservesPhysicalOuterControls() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(Configuration(profiles: [Profile(name: "Global", bindings: [
            PadBinding(index: 79, label: "Outer", color: .green, action: .shortcut(.copy))
        ])]))
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        coordinator.selectEditorModel(.virtual)
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(label: "Shared")
        coordinator.selectEditorModel(.launchpadX)
        #expect(coordinator.displayedBinding(at: 0)?.label == "Shared")
        #expect(coordinator.displayedBinding(at: 79)?.label == "Outer")
        #expect(coordinator.persistenceError == nil)
        #expect(try store.load().profiles[0].bindings.contains(where: { $0.label == "Shared" }))
    }
}
