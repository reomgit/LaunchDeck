// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Testing
@testable import LaunchDeckCore

@MainActor
struct AutomaticProfileTests {
    private final class Recording {
        var shortcuts: [Shortcut] = []
        var opened: [MacroStep] = []
    }

    private func withCoordinator(_ body: (AppCoordinator, ActiveAppMonitor, ProfileStore, Recording) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let global = Profile(name: "Global", bindings: [
            PadBinding(index: 56, label: "Gemini", color: .green, action: .step(.launchApplication(bundleIdentifier: "com.google.GeminiMacOS"))),
            PadBinding(index: 57, label: "Copy", color: .blue, action: .shortcut(.copy))
        ])
        let first = Profile(name: "First App", applicationBundleIdentifier: "test.first", bindings: [
            PadBinding(index: 57, label: "Paste", color: .orange, action: .shortcut(.paste))
        ])
        let second = Profile(name: "Second App", applicationBundleIdentifier: "test.second")
        let store = ProfileStore(directory: directory)
        try store.save(Configuration(profiles: [global, first, second]))
        let monitor = ActiveAppMonitor()
        let recording = Recording()
        let executor = ActionExecutor(dependencies: .init(
            canPostEvents: { true }, frontmostProcessID: { 42 },
            perform: { step in recording.opened.append(step); return 42 },
            postShortcut: { recording.shortcuts.append($0) }, postText: { _ in }))
        let coordinator = AppCoordinator(profileStore: store, actionExecutor: executor, appMonitor: monitor)
        defer { coordinator.shutdown() }
        try await body(coordinator, monitor, store, recording)
    }

    private func focus(_ bundleIdentifier: String?, monitor: ActiveAppMonitor) {
        monitor.onChange?(ActiveApplication(bundleIdentifier: bundleIdentifier, localizedName: "Target", processIdentifier: 42))
    }

    @Test("App focus switches two profiles and Global without changing the editor")
    func automaticallyFollowsFocus() async throws {
        try await withCoordinator { coordinator, monitor, _, _ in
            let editing = coordinator.selectedProfileID
            for (bundle, name, label) in [("test.first", "First App", "Paste"), ("test.second", "Second App", "Copy"), ("test.other", "Global", "Copy")] {
                focus(bundle, monitor: monitor)
                #expect(coordinator.runtimeProfile?.name == name)
                #expect(coordinator.activeLayout.binding(at: 57)?.label == label)
                #expect(coordinator.companionSnapshot().profileName == name)
                #expect(coordinator.companionSnapshot().controls[57].label == label)
                #expect(coordinator.companionSnapshot().mode == "Auto")
                #expect(coordinator.selectedProfileID == editing)
            }
            focus(nil, monitor: monitor)
            #expect(coordinator.runtimeProfile?.isGlobal == true)
        }
    }

    @Test("Global edits, inherited controls and Undo refresh the live deck immediately")
    func immediateInheritedEditsAndUndo() async throws {
        try await withCoordinator { coordinator, monitor, store, _ in
            focus("test.second", monitor: monitor)
            let manager = UndoManager()
            manager.groupsByEvent = false
            coordinator.setUndoManager(manager)
            coordinator.selectPad(57)
            manager.beginUndoGrouping()
            coordinator.updateSelectedBinding(label: "Updated Copy", color: .green)
            manager.endUndoGrouping()
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Updated Copy")
            #expect(coordinator.companionSnapshot().controls[57].label == "Updated Copy")
            #expect(coordinator.activeLayout.binding(at: 57)?.color == .green)
            let saved = try store.load()
            #expect(saved.profiles[0].bindings.first(where: { $0.index == 57 })?.label == "Updated Copy")
            manager.undo()
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Copy")
            #expect(coordinator.companionSnapshot().controls[57].label == "Copy")
            manager.redo()
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Updated Copy")
            focus("test.first", monitor: monitor)
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Paste")
        }
    }

    @Test("Editing an app profile takes effect when that app gains focus")
    func immediateAppEdits() async throws {
        try await withCoordinator { coordinator, monitor, _, _ in
            let first = try #require(coordinator.configuration.profiles.first { $0.name == "First App" })
            coordinator.selectProfile(first.id)
            coordinator.selectPad(57)
            coordinator.updateSelectedBinding(label: "New Paste")
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Copy")
            focus("test.first", monitor: monitor)
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "New Paste")
            coordinator.updateSelectedBinding(label: "Live Paste")
            #expect(coordinator.activeLayout.binding(at: 57)?.label == "Live Paste")
            #expect(coordinator.companionSnapshot().controls[57].label == "Live Paste")
        }
    }

    @Test("Advanced overrides pause app following and resume at the current app")
    func temporaryOverrideResumesAtCurrentApp() async throws {
        try await withCoordinator { coordinator, monitor, store, _ in
            coordinator.addManualProfile(name: "Temporary")
            let manualID = try #require(coordinator.selectedProfileID)
            #expect(coordinator.companion.onActivate?(manualID) == nil)
            focus("test.first", monitor: monitor)
            #expect(coordinator.runtimeProfile?.id == manualID)
            #expect(coordinator.runtimeDescription.contains("Temporary override"))
            #expect(coordinator.companionSnapshot().mode == "Manual")
            #expect(try store.load().manuallyActivatedProfileID == nil)
            #expect(coordinator.companion.onActivate?(nil) == nil)
            #expect(coordinator.runtimeProfile?.name == "First App")
            #expect(coordinator.companionSnapshot().mode == "Auto")
        }
    }

    @Test("Physical events select controls in the editor and dispatch outside it")
    func physicalRoutingRespectsEditorFocus() async throws {
        try await withCoordinator { coordinator, monitor, _, recording in
            let generation = coordinator.midi.connectionGeneration
            @MainActor func press(_ index: Int) {
                coordinator.midi.onPadEvent?(PadEvent(index: index, phase: .pressed, generation: generation))
                coordinator.midi.onPadEvent?(PadEvent(index: index, phase: .released, generation: generation))
            }
            focus(Bundle.main.bundleIdentifier, monitor: monitor)
            press(56)
            #expect(coordinator.selectedPadIndex == 56)
            #expect(recording.opened.isEmpty)
            press(57)
            #expect(coordinator.selectedPadIndex == 57)
            #expect(recording.shortcuts.isEmpty)
            focus("test.other", monitor: monitor)
            press(57)
            while coordinator.feedbackMessage == nil { await Task.yield() }
            #expect(recording.shortcuts == [.copy])
            coordinator.clearFeedback()
            press(56)
            while coordinator.feedbackMessage == nil { await Task.yield() }
            #expect(recording.opened == [.launchApplication(bundleIdentifier: "com.google.GeminiMacOS")])
            focus("test.first", monitor: monitor)
            coordinator.clearFeedback()
            press(57)
            while coordinator.feedbackMessage == nil { await Task.yield() }
            #expect(recording.shortcuts == [.copy, .paste])
        }
    }
}
