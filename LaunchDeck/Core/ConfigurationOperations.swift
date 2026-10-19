// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum ConfigurationOperations {
    static func materialize(profile: Profile, global: Profile?, name: String? = nil) -> Profile {
        let resolver = ProfileResolver()
        var result = Profile(name: name ?? profile.name, kind: .manual, pages: resolver.effectivePages(profile: profile, global: global), folders: resolver.effectiveFolders(profile: profile, global: global))
        result.modelOverridesEnabled = profile.modelOverridesEnabled
        var storedSource = profile
        storedSource.modelOverridesEnabled = true
        var storedGlobal = global
        storedGlobal?.modelOverridesEnabled = true
        for model in DeviceModel.allCases where model != .miniMK3 {
            let preserveDormant = !profile.modelOverridesEnabled && profile.storedModels.contains(model)
            let source = preserveDormant ? storedSource : profile
            let inheritance = preserveDormant ? storedGlobal : global
            result.setLayout(DeckModelLayout(pages: resolver.effectivePages(profile: source, global: inheritance, model: model), folders: resolver.effectiveFolders(profile: source, global: inheritance, model: model)), for: model)
        }
        return result
    }
    struct LayoutCopyPreview: Sendable {
        let layout: DeckModelLayout
        let unmappedBindings: [PadBinding]
        let mappings: [Int: Int]
    }
    static func previewCopy(profile: Profile, global: Profile?, from source: DeviceModel, to target: DeviceModel) -> LayoutCopyPreview {
        let resolver = ProfileResolver()
        let sourceControls = source.descriptor.controls
        let targetControls = target.descriptor.controls
        let mappings = Dictionary(uniqueKeysWithValues: sourceControls.compactMap { control -> (Int, Int)? in
            guard let destination = targetControls.first(where: { $0.row == control.row && $0.column == control.column }) else { return nil }
            return (control.index, destination.index)
        })
        var pages = resolver.effectivePages(profile: profile, global: global, model: source)
        var unmapped: [PadBinding] = []
        for page in pages.indices {
            pages[page].bindings = pages[page].bindings.compactMap { binding in
                guard let index = mappings[binding.index] else { unmapped.append(binding); return nil }
                return PadBinding(index: index, label: binding.label, color: binding.color, action: binding.action, symbolName: binding.symbolName, artworkID: binding.artworkID, pressEffect: binding.pressEffect)
            }
        }
        return LayoutCopyPreview(layout: DeckModelLayout(pages: pages, folders: resolver.effectiveFolders(profile: profile, global: global, model: source)), unmappedBindings: unmapped, mappings: mappings)
    }
    static func copyLayout(profile: inout Profile, global: Profile?, from source: DeviceModel, to target: DeviceModel) {
        profile.setLayout(previewCopy(profile: profile, global: global, from: source, to: target).layout, for: target)
    }
}
