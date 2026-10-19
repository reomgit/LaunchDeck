// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// An editor snapshot retains explicit disabled bindings, unlike the executable layout.
@MainActor
final class EditorLayoutSnapshot {
    let pages: [DeckPage]
    let folders: [DeckFolder]
    private let bindings: [UUID: [Int: PadBinding]]
    private let localBindings: [UUID: [Int: PadBinding]]
    private let inherits: Bool

    init(profile: Profile?, global: Profile?, model: DeviceModel) {
        let resolver = ProfileResolver()
        pages = profile.map { resolver.effectivePages(profile: $0, global: global, model: model) } ?? []
        folders = profile.map { resolver.effectiveFolders(profile: $0, global: global, model: model) } ?? []
        inherits = profile?.kind == .application
        func index(_ pages: [DeckPage]) -> [UUID: [Int: PadBinding]] {
            var result: [UUID: [Int: PadBinding]] = [:]
            for page in pages {
                var controls: [Int: PadBinding] = [:]
                for binding in page.bindings { controls[binding.index] = binding }
                result[page.id] = controls
            }
            return result
        }
        bindings = index(pages)
        localBindings = index(profile?.layoutForEditing(model).pages ?? [])
    }
    func displayedBinding(at index: Int, pageID: UUID) -> PadBinding? { bindings[pageID]?[index] }
    func rawBinding(at index: Int, pageID: UUID) -> PadBinding? { localBindings[pageID]?[index] }
    func isInherited(at index: Int, pageID: UUID) -> Bool {
        inherits && localBindings[pageID]?[index] == nil && bindings[pageID]?[index] != nil
    }
}

@MainActor
final class EditorLayoutCache {
    private struct Key: Hashable { let profileID: UUID?; let model: DeviceModel }
    private var snapshots: [Key: EditorLayoutSnapshot] = [:]
    func invalidate() { snapshots.removeAll(keepingCapacity: true) }
    func snapshot(configuration: Configuration, profileID: UUID?, model: DeviceModel) -> EditorLayoutSnapshot {
        let key = Key(profileID: profileID, model: model)
        if let snapshot = snapshots[key] { return snapshot }
        let snapshot = EditorLayoutSnapshot(profile: configuration.profiles.first { $0.id == profileID }, global: configuration.profiles.first(where: \.isGlobal), model: model)
        snapshots[key] = snapshot
        return snapshot
    }
}
