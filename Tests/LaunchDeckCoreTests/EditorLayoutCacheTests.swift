// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation
import Testing
@testable import LaunchDeckCore

@MainActor
struct EditorLayoutCacheTests {
    @Test("Editor snapshots reuse a merge across page reads and isolate profiles and models")
    func reuseAndIsolation() throws {
        let second = DeckPage(id: UUID(), name: "Second", bindings: [binding("Second", index: 3)])
        let global = Profile(name: "Global", pages: [DeckPage(bindings: [binding("Mini")]), second])
        var app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        app.modelOverridesEnabled = true
        app.setLayout(DeckModelLayout(pages: [DeckPage(bindings: [binding("Pro")])]), for: .proMK3)
        let configuration = Configuration(profiles: [global, app])
        let cache = EditorLayoutCache()
        let snapshot = cache.snapshot(configuration: configuration, profileID: app.id, model: .miniMK3)
        #expect(snapshot.displayedBinding(at: 0, pageID: DeckPage.homeID)?.label == "Mini")
        #expect(snapshot.displayedBinding(at: 3, pageID: second.id)?.label == "Second")
        #expect(cache.snapshot(configuration: configuration, profileID: app.id, model: .miniMK3) === snapshot)
        let pro = cache.snapshot(configuration: configuration, profileID: app.id, model: .proMK3)
        #expect(pro !== snapshot)
        #expect(pro.displayedBinding(at: 0, pageID: DeckPage.homeID)?.label == "Pro")
        let globalSnapshot = cache.snapshot(configuration: configuration, profileID: global.id, model: .miniMK3)
        #expect(globalSnapshot !== snapshot)
        #expect(!globalSnapshot.isInherited(at: 0, pageID: DeckPage.homeID))
        #expect(cache.snapshot(configuration: configuration, profileID: UUID(), model: .miniMK3).pages.isEmpty)
    }

    @Test("Invalidation refreshes global inheritance, local disabled bindings and folder order")
    func invalidationAndDisabledBindings() {
        let folder = DeckFolder(name: "Tools")
        var global = Profile(name: "Global", bindings: [binding("Inherited"), binding("Off", index: 1, action: .disabled)], folders: [folder])
        var app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        let cache = EditorLayoutCache()
        let initial = cache.snapshot(configuration: Configuration(profiles: [global, app]), profileID: app.id, model: .miniMK3)
        #expect(initial.isInherited(at: 0, pageID: DeckPage.homeID))
        #expect(initial.displayedBinding(at: 1, pageID: DeckPage.homeID)?.action == .disabled)
        #expect(initial.isInherited(at: 1, pageID: DeckPage.homeID))
        global.bindings[0].label = "Changed"
        global.folders[0].name = "Renamed"
        app.bindings = [binding("Disabled", action: .disabled)]
        cache.invalidate()
        let updated = cache.snapshot(configuration: Configuration(profiles: [global, app]), profileID: app.id, model: .miniMK3)
        #expect(updated !== initial)
        #expect(updated.displayedBinding(at: 0, pageID: DeckPage.homeID)?.action == .disabled)
        #expect(updated.rawBinding(at: 0, pageID: DeckPage.homeID)?.label == "Disabled")
        #expect(!updated.isInherited(at: 0, pageID: DeckPage.homeID))
        #expect(updated.folders.first?.name == "Renamed")
        #expect(initial.displayedBinding(at: 0, pageID: DeckPage.homeID)?.label == "Inherited")
        app.bindings = []
        cache.invalidate()
        #expect(cache.snapshot(configuration: Configuration(profiles: [global, app]), profileID: app.id, model: .miniMK3).displayedBinding(at: 0, pageID: DeckPage.homeID)?.label == "Changed")
    }

    @Test("Warm editor reads still observe configuration, page, profile and model changes")
    func coordinatorObservationAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let global = Profile(name: "Global", bindings: [binding("Global")])
        let app = Profile(name: "App", applicationBundleIdentifier: "test.app")
        let store = ProfileStore(directory: directory)
        try store.save(Configuration(profiles: [global, app]))
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        let undo = UndoManager(); coordinator.setUndoManager(undo)
        coordinator.selectedProfileID = app.id
        _ = coordinator.displayedBinding(at: 0)
        let configurationChange = ChangeFlag()
        withObservationTracking {
            #expect(coordinator.displayedBinding(at: 0)?.label == "Global")
            #expect(coordinator.isInherited(at: 0))
        } onChange: { configurationChange.set() }
        undo.beginUndoGrouping()
        coordinator.selectPad(0); coordinator.disableSelectedPad()
        undo.endUndoGrouping()
        #expect(configurationChange.value)
        #expect(coordinator.displayedBinding(at: 0)?.action == .disabled)
        #expect(!coordinator.isInherited(at: 0))
        undo.undo()
        #expect(coordinator.displayedBinding(at: 0)?.label == "Global")
        #expect(coordinator.isInherited(at: 0))
        #expect(try store.load().profiles.first(where: { $0.id == app.id })?.bindings.isEmpty == true)
        let profileChange = ChangeFlag()
        withObservationTracking { _ = coordinator.displayedBinding(at: 0) } onChange: { profileChange.set() }
        coordinator.selectedProfileID = global.id
        #expect(profileChange.value)
        let modelChange = ChangeFlag()
        withObservationTracking { _ = coordinator.editorPages } onChange: { modelChange.set() }
        coordinator.selectEditorModel(.proMK3)
        #expect(modelChange.value)
        #expect(coordinator.displayedBinding(at: 0)?.label == "Global")
        coordinator.createPage(name: "Second")
        coordinator.selectPage(DeckPage.homeID)
        let pageChange = ChangeFlag()
        withObservationTracking { _ = coordinator.displayedBinding(at: 0) } onChange: { pageChange.set() }
        coordinator.selectPage(try #require(coordinator.editorPages.last?.id))
        #expect(pageChange.value)
        #expect(coordinator.selectedPage?.name == "Second")
    }

    private func binding(_ label: String, index: Int = 0, action: BindingAction = .shortcut(.copy)) -> PadBinding {
        PadBinding(index: index, label: label, color: .blue, action: action)
    }
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool { lock.withLock { changed } }
    func set() { lock.withLock { changed = true } }
}
