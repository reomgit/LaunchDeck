// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Testing
@testable import LaunchDeckCore

@MainActor
struct EventualCoordinatorTests {
    private final class Recording {
        var steps: [MacroStep] = []
    }
    private func withCoordinator(_ body: (AppCoordinator, ProfileStore, Recording) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(.default)
        let recording = Recording()
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 42 }, perform: { step in recording.steps.append(step); return nil }, postShortcut: { _ in }, postText: { _ in }))
        let coordinator = AppCoordinator(profileStore: store, actionExecutor: executor)
        // These tests explicitly exercise optional model-specific layouts.
        coordinator.setModelOverridesEnabled(true)
        defer { coordinator.shutdown() }
        try await body(coordinator, store, recording)
    }
    @Test func editorAssignmentsStayIndependentForEveryModelAndPersist() async throws {
        try await withCoordinator { coordinator, store, _ in
            for model in DeviceModel.allCases {
                coordinator.selectEditorModel(model)
                let index = model.descriptor.controlCount - 1
                coordinator.selectPad(index)
                coordinator.updateSelectedBinding(label: model.rawValue)
            }
            for model in DeviceModel.allCases {
                coordinator.selectEditorModel(model)
                #expect(coordinator.displayedBinding(at: model.descriptor.controlCount - 1)?.label == model.rawValue)
                #expect(coordinator.selectedProfile?.layout(for: model).pages[0].bindings.count == 1)
            }
            #expect(coordinator.persistenceError == nil)
            let loaded = try store.load()
            #expect(loaded == coordinator.configuration)
        }
    }
    @Test func copyPreviewReportsPerimeterLossAndCopyPreservesSource() async throws {
        try await withCoordinator { coordinator, _, _ in
            coordinator.selectEditorModel(.proMK3)
            coordinator.selectPad(104); coordinator.updateSelectedBinding(label: "Shift")
            coordinator.selectPad(0); coordinator.updateSelectedBinding(label: "Grid")
            let source = try #require(coordinator.selectedProfile).layout(for: .proMK3)
            let preview = try #require(coordinator.copyPreview(to: .virtual))
            #expect(preview.unmappedBindings.map(\.index) == [104])
            #expect(coordinator.selectedProfile?.layout(for: .virtual).pages[0].bindings.isEmpty == true)
            coordinator.copySelectedLayout(to: .virtual)
            #expect(coordinator.selectedProfile?.layout(for: .proMK3) == source)
            coordinator.selectEditorModel(.virtual)
            #expect(coordinator.displayedBinding(at: 0)?.label == "Grid")
            #expect(coordinator.displayedBinding(at: 104) == nil)
        }
    }
    @Test func applicationInheritanceAndOverridesStayWithinTheirModel() async throws {
        try await withCoordinator { coordinator, _, _ in
            for model in DeviceModel.allCases {
                coordinator.selectEditorModel(model)
                coordinator.selectPad(0); coordinator.updateSelectedBinding(label: model.rawValue)
            }
            coordinator.addApplicationProfile(bundleIdentifier: "example.model.app", name: "Application")
            coordinator.setModelOverridesEnabled(true)
            coordinator.selectEditorModel(.launchpadX)
            #expect(coordinator.isInherited(at: 0))
            coordinator.selectPad(0); coordinator.updateSelectedBinding(label: "Override X")
            coordinator.selectEditorModel(.proMK3)
            #expect(coordinator.displayedBinding(at: 0)?.label == "proMK3")
            #expect(coordinator.isInherited(at: 0))
            coordinator.selectEditorModel(.launchpadX)
            #expect(coordinator.displayedBinding(at: 0)?.label == "Override X")
            coordinator.selectPad(0); coordinator.clearSelectedPad()
            #expect(coordinator.displayedBinding(at: 0)?.label == "launchpadX")
            #expect(coordinator.isInherited(at: 0))
        }
    }
    @Test func companionSnapshotUsesIndependentVirtualBindingsAndCoordinates() async throws {
        try await withCoordinator { coordinator, _, _ in
            coordinator.selectPad(0); coordinator.updateSelectedBinding(label: "Physical")
            coordinator.selectEditorModel(.virtual)
            coordinator.selectPad(0); coordinator.updateSelectedBinding(label: "Phone", color: .green)
            let snapshot = coordinator.companionSnapshot()
            #expect(snapshot.model == "virtual" && snapshot.controls.count == 64)
            #expect(snapshot.controls.first?.label == "Phone")
            #expect(snapshot.controls.first?.row == 7 && snapshot.controls.first?.column == 0)
            #expect(coordinator.activeLayout.binding(at: 0)?.label == "Physical")
        }
    }
    @Test func staleRemotePressCannotDispatchAChangedAssignment() async throws {
        try await withCoordinator { coordinator, _, recording in
            coordinator.selectEditorModel(.virtual)
            coordinator.selectPad(0); coordinator.updateSelectedBinding(label: "Before", action: .step(.openWebsite("https://example.com")))
            let before = coordinator.companionSnapshot()
            coordinator.updateSelectedBinding(label: "After")
            #expect(coordinator.pressCompanion(index: 0, revision: before.revision, pageID: before.pageID) != nil)
            #expect(recording.steps.isEmpty)
            let after = coordinator.companionSnapshot()
            #expect(coordinator.pressCompanion(index: 0, revision: after.revision, pageID: after.pageID) == nil)
            for _ in 0..<50 where recording.steps.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
            #expect(recording.steps == [.openWebsite("https://example.com")])
        }
    }
    @Test func virtualFolderNavigationDoesNotChangePhysicalPage() async throws {
        try await withCoordinator { coordinator, _, _ in
            coordinator.createFolder(name: "Physical folder")
            coordinator.executeNavigation(.openFolder(try #require(coordinator.editorFolders.first).id))
            let physical = coordinator.runtimePage?.id
            coordinator.selectEditorModel(.virtual)
            coordinator.createFolder(name: "Virtual folder")
            let folder = try #require(coordinator.editorFolders.first)
            let virtualPage = coordinator.selectedPageID
            coordinator.selectPad(0); coordinator.updateSelectedBinding(action: .navigation(.back))
            coordinator.selectPage(DeckPage.homeID)
            coordinator.selectPad(0); coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id)))
            let home = coordinator.companionSnapshot()
            #expect(coordinator.pressCompanion(index: 0, revision: home.revision, pageID: home.pageID) == nil)
            let opened = coordinator.companionSnapshot()
            #expect(opened.pageID == virtualPage)
            #expect(coordinator.runtimePage?.id == physical)
            #expect(coordinator.pressCompanion(index: 0, revision: home.revision, pageID: home.pageID) != nil)
            #expect(coordinator.pressCompanion(index: 0, revision: opened.revision, pageID: opened.pageID) == nil)
            #expect(coordinator.companionSnapshot().pageID == DeckPage.homeID)
            #expect(coordinator.runtimePage?.id == physical)
        }
    }
    @Test func manualActivationAndAutoSynchronizeCompanionAndDesktop() async throws {
        try await withCoordinator { coordinator, store, _ in
            let global = try #require(coordinator.globalProfile)
            coordinator.addManualProfile(name: "Presentation")
            let manual = try #require(coordinator.selectedProfileID)
            #expect(coordinator.companionSnapshot().profileID == global.id)
            coordinator.activateSelectedProfile()
            #expect(coordinator.runtimeProfile?.id == manual)
            #expect(coordinator.companionSnapshot().profileID == manual)
            #expect(coordinator.companionSnapshot().mode == "Manual")
            #expect(try store.load().manuallyActivatedProfileID == nil)
            coordinator.useAutoProfiles()
            #expect(coordinator.companionSnapshot().profileID == global.id)
            #expect(coordinator.companionSnapshot().mode == "Auto")
        }
    }
}

extension EventualCoordinatorTests {
    @Test func companionSnapshotOmitsActionSourcesURLsBookmarksAndSecrets() async throws {
        try await withCoordinator { coordinator, _, _ in
            coordinator.selectEditorModel(.virtual)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("PRIVATE_BOOKMARK_" + UUID().uuidString)
            try Data().write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let steps: [MacroStep] = [
                .httpRequest(HTTPRequestAction(url: "http://localhost/status?token=PRIVATE_HTTP", headers: ["X-Test": "PRIVATE_HEADER"], body: "PRIVATE_BODY", allowedHosts: ["localhost"], secretHeaders: ["Authorization": "PRIVATE_REFERENCE"])),
                .script(ScriptAction(source: .inline("echo PRIVATE_SCRIPT"), language: .shell, arguments: ["PRIVATE_ARGUMENT"])),
                .openWebsite("https://example.com/PRIVATE_WEBSITE"),
                .text("PRIVATE_TEXT"),
                .openFile(try FileTarget(url: file)),
                .extensionAction(ExtensionInvocation(extensionID: "example", actionID: "echo", parameters: ["value": "PRIVATE_PARAMETER"]))
            ]
            for (index, step) in steps.enumerated() {
                coordinator.selectPad(index); coordinator.updateSelectedBinding(label: "Safe action", action: .step(step))
            }
            let bytes = try JSONEncoder().encode(coordinator.companionSnapshot())
            let payload = try #require(String(data: bytes, encoding: .utf8))
            #expect(!payload.contains("PRIVATE_"))
            #expect(!payload.contains("bookmark"))
            #expect(payload.contains("Safe action"))
        }
    }
}
