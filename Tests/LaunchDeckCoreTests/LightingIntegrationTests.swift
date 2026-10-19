import Foundation
import Testing
@testable import LaunchDeckCore

struct LightingIntegrationTests {
    @Test @MainActor func unchangedCompanionLayoutKeepsRunningFeedbackAcrossOtherPageEdits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(Configuration(profiles: [Profile(name: "Global", bindings: [
            PadBinding(index: 0, label: "Wait", color: .blue, action: .macro([.delay(milliseconds: 1), .openWebsite("https://example.com")]))
        ])]))
        var waiting: CheckedContinuation<Void, Never>?
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 42 }, perform: { _ in nil }, postShortcut: { _ in }, postText: { _ in }, sleep: { _ in await withCheckedContinuation { waiting = $0 } }))
        let coordinator = AppCoordinator(profileStore: store, actionExecutor: executor)
        defer { coordinator.shutdown() }
        try coordinator.companion.start(loopbackOnly: true)
        for _ in 0..<200 where !coordinator.companion.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        try #require(coordinator.companion.isRunning)
        let before = coordinator.companionSnapshot()
        #expect(coordinator.pressCompanion(index: 0, revision: before.revision, pageID: before.pageID) == nil)
        while waiting == nil { await Task.yield() }
        try await Task.sleep(for: .milliseconds(60))
        coordinator.createPage(name: "Unrelated")
        #expect(coordinator.companionSnapshot().controls[0].color != "#3CB4FF")
        waiting?.resume()
        while executor.isRunning { await Task.yield() }
        try await Task.sleep(for: .milliseconds(60))
        #expect(coordinator.companionSnapshot().controls[0].color == "#30FF8C")
    }

    @Test @MainActor func completedOldActionCannotPaintANewerCompanionAssignment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        try store.save(Configuration(profiles: [Profile(name: "Global", bindings: [
            PadBinding(index: 0, label: "Before", color: .blue, action: .macro([.delay(milliseconds: 1), .openWebsite("https://example.com")]))
        ])]))
        var waiting: CheckedContinuation<Void, Never>?
        let executor = ActionExecutor(dependencies: .init(canPostEvents: { true }, frontmostProcessID: { 42 }, perform: { _ in nil }, postShortcut: { _ in }, postText: { _ in }, sleep: { _ in await withCheckedContinuation { waiting = $0 } }))
        let coordinator = AppCoordinator(profileStore: store, actionExecutor: executor)
        defer { coordinator.shutdown() }
        try coordinator.companion.start(loopbackOnly: true)
        for _ in 0..<200 where !coordinator.companion.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        try #require(coordinator.companion.isRunning)
        let before = coordinator.companionSnapshot()
        #expect(coordinator.pressCompanion(index: 0, revision: before.revision, pageID: before.pageID) == nil)
        while waiting == nil { await Task.yield() }
        coordinator.selectPad(0)
        coordinator.updateSelectedBinding(label: "After", color: .orange, action: .shortcut(.paste))
        waiting?.resume()
        while executor.isRunning { await Task.yield() }
        try await Task.sleep(for: .milliseconds(60))
        #expect(coordinator.companionSnapshot().controls[0].color == "#FF8414")
    }

    private func configurationData(lighting: [String: Any]) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Configuration.default)) as? [String: Any])
        var profiles = try #require(object["profiles"] as? [[String: Any]])
        var pages = try #require(profiles[0]["pages"] as? [[String: Any]])
        pages[0]["lighting"] = lighting
        profiles[0]["pages"] = pages
        object["profiles"] = profiles
        return try JSONSerialization.data(withJSONObject: object)
    }

    private var validLighting: [String: Any] {
        ["pressEffect": "ripple", "ambientEffect": "none", "brightness": 0.5, "speed": 1.0,
         "accentColor": ["red": 30, "green": 90, "blue": 127], "showsActionStatus": true, "showsApplicationStatus": true]
    }

    @Test func persistedPageLightingSurvivesLoadAndSave() throws {
        let decoded = try JSONDecoder().decode(Configuration.self, from: configurationData(lighting: validLighting))
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        let profiles = try #require(object["profiles"] as? [[String: Any]])
        let pages = try #require(profiles[0]["pages"] as? [[String: Any]])
        let saved = try #require(pages[0]["lighting"] as? [String: Any])
        #expect(saved["pressEffect"] as? String == "ripple")
        #expect(saved["brightness"] as? Double == 0.5)
    }

    @Test func invalidPageLightingIsRejected() throws {
        var lighting = validLighting
        lighting["brightness"] = 2.0
        #expect(throws: (any Error).self) {
            let decoded = try JSONDecoder().decode(Configuration.self, from: configurationData(lighting: lighting))
            try ProfileStore().validate(decoded)
        }
    }

    @Test func dormantLightingIsValidatedAndPortableCopiesKeepArtAndPadEffects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pixels = Array(repeating: PadColor.off, count: 64)
        pixels[56] = .green; pixels[0] = .orange
        let settings = LightingSettings(pressEffect: .ripple, brightness: 0.5, gridArtwork: pixels)
        var profile = Profile(name: "Portable", kind: .manual, pages: [DeckPage(bindings: [
            PadBinding(index: 0, label: "Keep Action", color: .blue, action: .shortcut(.paste), pressEffect: .sparkle)
        ], lighting: settings)])
        profile.setLayout(DeckModelLayout(pages: [DeckPage(lighting: LightingSettings(speed: 0))]), for: .proMK3)
        #expect(throws: (any Error).self) { try ProfileStore().validate(Configuration(profiles: [Profile(name: "Global"), profile])) }
        profile.setLayout(DeckModelLayout(pages: [DeckPage(lighting: settings)]), for: .proMK3)
        let copy = ConfigurationOperations.previewCopy(profile: profile, global: nil, from: .miniMK3, to: .virtual)
        #expect(copy.layout.pages[0].lighting?.gridArtwork?[56] == .green)
        #expect(copy.layout.pages[0].bindings[0].pressEffect == .sparkle)
        let package = directory.appendingPathComponent("lighting.launchdeckprofile")
        let store = ProfilePackageStore(directory: directory)
        try store.export(profile: profile, global: nil, to: package)
        let imported = try store.importProfile(from: package)
        #expect(imported.pages[0].lighting == settings)
        #expect(imported.bindings[0].pressEffect == .sparkle)
        #expect(imported.bindings[0].action == .shortcut(.paste))
        #expect(imported.storedLayout(for: .proMK3).pages[0].lighting == settings)
    }

    @Test func applicationIndicatorsOnlyReportKnownRunningLaunchActions() {
        let profile = Profile(name: "Global", bindings: [
            PadBinding(index: 0, label: "Active", color: .blue, action: .step(.launchApplication(bundleIdentifier: "example.active"))),
            PadBinding(index: 1, label: "Running", color: .blue, action: .step(.launchApplication(bundleIdentifier: "example.background"))),
            PadBinding(index: 2, label: "Closed", color: .blue, action: .step(.launchApplication(bundleIdentifier: "example.closed"))),
            PadBinding(index: 3, label: "Unknown toggle", color: .blue, action: .shortcut(.copy)),
            PadBinding(index: 4, label: "Sequence", color: .blue, action: .macro([.launchApplication(bundleIdentifier: "example.active")]))
        ])
        let layout = ProfileResolver().resolve(profiles: [profile], bundleIdentifier: nil, revision: 1)
        let states = LightingStatusResolver.applicationStates(layout: layout, runningBundleIDs: ["example.active", "example.background"], frontmostBundleID: "example.active")
        #expect(states == [0: .frontmost, 1: .running])
        #expect(LightingStatusResolver.applicationStates(layout: layout, runningBundleIDs: [], frontmostBundleID: "example.active").isEmpty)
    }

    @Test @MainActor func pageEditsInheritLightingAndPaintingPreservesActionsAndDisabledDarkness() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(directory: directory)
        let settings = LightingSettings(pressEffect: .cross, brightness: 0.5)
        let global = Profile(name: "Global", pages: [DeckPage(bindings: [
            PadBinding(index: 0, label: "Action", color: .blue, action: .shortcut(.copy)),
            PadBinding(index: 1, label: "Off", color: .orange, action: .disabled),
            PadBinding(index: 79, label: "Outer", color: .green, action: .shortcut(.paste))
        ], lighting: settings)])
        try store.save(Configuration(profiles: [global]))
        let coordinator = AppCoordinator(profileStore: store)
        defer { coordinator.shutdown() }
        coordinator.addApplicationProfile(bundleIdentifier: "example.inherits", name: "App")
        #expect(coordinator.selectedLightingSettings == settings)
        coordinator.renamePage(DeckPage.homeID, name: "Renamed")
        #expect(coordinator.selectedProfile?.pages[0].lighting == nil)
        coordinator.startLightingPreview()
        coordinator.selectEditorModel(.virtual)
        coordinator.paintGridPixel(index: 56, color: .green)
        coordinator.paintGridPixel(index: 1, color: .orange)
        #expect(coordinator.selectedLightingSettings.gridArtwork?[56] == .green)
        #expect(coordinator.lighting.previewColors[1] == .off)
        #expect(coordinator.displayedBinding(at: 0)?.action == .shortcut(.copy))
        coordinator.selectPad(0); coordinator.setSelectedPressEffect(.sparkle)
        coordinator.assign(try #require(coordinator.displayedBinding(at: 0)), to: 2)
        #expect(coordinator.displayedBinding(at: 2)?.pressEffect == .sparkle)
        coordinator.selectEditorModel(.proMK3)
        #expect(coordinator.displayedBinding(at: 79)?.label == "Outer")
        var audio = coordinator.selectedLightingSettings; audio.ambientEffect = .audioMeter
        coordinator.updatePageLighting(audio)
        #expect(!coordinator.lighting.audio.isEnabled && !coordinator.lighting.audio.isCapturing)
        coordinator.updatePageLighting(nil)
        #expect(coordinator.selectedLightingSettings == settings)
        #expect(try store.load() == coordinator.configuration)
    }
}
