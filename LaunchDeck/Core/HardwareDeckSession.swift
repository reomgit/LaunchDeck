// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Observation

/// One physical unit's state; profile mappings are supplied by the coordinator.
@MainActor
@Observable
final class HardwareDeckSession {
    let deviceID: Int32
    let model: DeviceModel
    let generation: Int
    let renderer: LEDRenderer
    private(set) var layout: ResolvedLayout
    private var navigation = DeckNavigation()
    private var heldPads = Set<Int>()
    private var profileID: UUID?
    private var renderedPageID: UUID?
    private var renderedPaused = false
    private var pages: [DeckPage] = []
    private var folders: [DeckFolder] = []
    var pageID: UUID { navigation.pageID }

    init(deviceID: Int32, model: DeviceModel, generation: Int, send: @escaping ([UInt8]) -> Void) {
        self.deviceID = deviceID; self.model = model; self.generation = generation
        renderer = LEDRenderer(model: { model }, send: send)
        layout = ResolvedLayout(revision: 0, pads: Array(repeating: ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: false), count: model.descriptor.controlCount), model: model)
    }

    func update(profiles: [Profile], bundleIdentifier: String?, profileID: UUID?, revision: Int, paused: Bool) {
        let resolver = ProfileResolver()
        let profile = profileID.flatMap { id in profiles.first { $0.id == id } }
            ?? resolver.activeProfile(profiles: profiles, bundleIdentifier: bundleIdentifier)
        let global = profiles.first(where: \.isGlobal)
        pages = profile.map { resolver.effectivePages(profile: $0, global: global, model: model) } ?? []
        folders = profile.map { resolver.effectiveFolders(profile: $0, global: global, model: model) } ?? []
        let profileChanged = self.profileID != profile?.id
        if profileChanged {
            navigation.reset(pages: pages); heldPads.removeAll()
        } else { navigation.reconcile(pages: pages) }
        self.profileID = profile?.id
        let resolved = resolver.resolve(profiles: profiles, bundleIdentifier: bundleIdentifier, revision: revision,
            profileID: profile?.id, pageID: navigation.pageID, model: model)
        let contentChanged = !layout.hasSameContent(as: resolved)
        guard profileChanged || contentChanged || renderedPageID != navigation.pageID || renderedPaused != paused else { return }
        layout = resolved
        renderedPageID = navigation.pageID; renderedPaused = paused
        renderer.render(layout, paused: paused)
    }

    func navigate(_ action: NavigationAction) -> Bool {
        navigation.perform(action, pages: pages, folders: folders)
    }

    /// Releases update only this unit; stale and duplicate presses cannot run actions.
    func accept(_ event: PadEvent) -> Bool {
        guard event.generation == generation, (0..<model.descriptor.controlCount).contains(event.index) else { return false }
        switch event.phase {
        case .released: heldPads.remove(event.index); return false
        case .pressed: return heldPads.insert(event.index).inserted
        }
    }

    func clearHeldPads() { heldPads.removeAll() }
}
