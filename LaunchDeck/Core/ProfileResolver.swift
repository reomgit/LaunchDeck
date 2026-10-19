// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct ProfileResolver: Sendable {
    func activeProfile(profiles: [Profile], bundleIdentifier: String?, manuallyActivatedProfileID: UUID? = nil) -> Profile? {
        if let id = manuallyActivatedProfileID, let manual = profiles.first(where: { $0.id == id }) { return manual }
        return profiles.first { $0.kind == .application && $0.applicationBundleIdentifier == bundleIdentifier } ?? profiles.first(where: \.isGlobal)
    }
    func effectivePages(profile: Profile, global: Profile?, model: DeviceModel = .miniMK3) -> [DeckPage] {
        let layout = profile.layout(for: model)
        guard profile.kind == .application, let global else { return ordered(layout.pages, by: layout.pageOrder) }
        var result = global.layout(for: model).pages
        for page in layout.pages {
            if let index = result.firstIndex(where: { $0.id == page.id }) {
                var merged = result[index]
                merged.name = page.name; merged.folderID = page.folderID
                merged.lighting = page.lighting ?? merged.lighting
                let overridden = Set(page.bindings.map(\.index))
                merged.bindings = merged.bindings.filter { !overridden.contains($0.index) } + page.bindings
                result[index] = merged
            } else { result.append(page) }
        }
        return ordered(result, by: layout.pageOrder ?? global.layout(for: model).pageOrder)
    }
    func effectiveFolders(profile: Profile, global: Profile?, model: DeviceModel = .miniMK3) -> [DeckFolder] {
        let layout = profile.layout(for: model)
        guard profile.kind == .application, let global else { return ordered(layout.folders, by: layout.folderOrder) }
        var result = global.layout(for: model).folders
        for folder in layout.folders {
            if let index = result.firstIndex(where: { $0.id == folder.id }) { result[index] = folder }
            else { result.append(folder) }
        }
        return ordered(result, by: layout.folderOrder ?? global.layout(for: model).folderOrder)
    }
    private func ordered<T: Identifiable>(_ items: [T], by order: [UUID]?) -> [T] where T.ID == UUID {
        guard let order else { return items }
        let first = order.compactMap { id in items.first { $0.id == id } }
        return first + items.filter { !order.contains($0.id) }
    }
    func resolve(profiles: [Profile], bundleIdentifier: String?, revision: Int, profileID: UUID? = nil, pageID: UUID? = nil, model: DeviceModel = .miniMK3) -> ResolvedLayout {
        let global = profiles.first(where: \.isGlobal)
        let active = profileID.flatMap { id in profiles.first { $0.id == id } } ?? activeProfile(profiles: profiles, bundleIdentifier: bundleIdentifier)
        let pageID = pageID ?? DeckPage.homeID
        let local = active?.layout(for: model).pages.first { $0.id == pageID }?.bindings ?? []
        let inherited = active?.kind == .application ? (global?.layout(for: model).pages.first { $0.id == pageID }?.bindings ?? []) : []
        let pads = (0..<model.descriptor.controlCount).map { index -> ResolvedPad in
            let binding = local.first { $0.index == index } ?? inherited.first { $0.index == index }
            let source = local.contains { $0.index == index } ? active?.id : global?.id
            guard let binding else { return ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: false) }
            if case .disabled = binding.action { return ResolvedPad(binding: nil, sourceProfileID: source, isDisabled: true) }
            return ResolvedPad(binding: binding, sourceProfileID: source, isDisabled: false)
        }
        let lighting = active.flatMap { profile in effectivePages(profile: profile, global: global, model: model).first { $0.id == pageID }?.lighting } ?? LightingSettings()
        return ResolvedLayout(revision: revision, pads: pads, model: model, lighting: lighting)
    }
}
