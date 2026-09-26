// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

struct ProfileResolver: Sendable {
    func resolve(profiles: [Profile], bundleIdentifier: String?, revision: Int) -> ResolvedLayout {
        let global = profiles.first(where: \.isGlobal)
        let application = bundleIdentifier.flatMap { identifier in
            profiles.first { $0.applicationBundleIdentifier == identifier }
        }

        let globalBindings = bindingsByIndex(global)
        let appBindings = bindingsByIndex(application)

        let pads = (0..<64).map { index in
            if let binding = appBindings[index] {
                return resolvedPad(for: binding, source: application?.id)
            }
            if let binding = globalBindings[index] {
                return resolvedPad(for: binding, source: global?.id)
            }
            return ResolvedPad(binding: nil, sourceProfileID: nil, isDisabled: false)
        }
        return ResolvedLayout(revision: revision, pads: pads)
    }

    private func bindingsByIndex(_ profile: Profile?) -> [Int: PadBinding] {
        (profile?.bindings ?? []).reduce(into: [:]) { bindings, binding in
            bindings[binding.index] = binding
        }
    }

    private func resolvedPad(for binding: PadBinding, source: UUID?) -> ResolvedPad {
        if case .disabled = binding.action {
            return ResolvedPad(binding: nil, sourceProfileID: source, isDisabled: true)
        }
        return ResolvedPad(binding: binding, sourceProfileID: source, isDisabled: false)
    }
}
