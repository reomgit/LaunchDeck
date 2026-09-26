// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import ApplicationServices
import Observation

@MainActor
@Observable
final class PermissionService {
    private(set) var accessibilityTrusted = false
    private(set) var eventPostingAllowed = false

    var canPostEvents: Bool {
        accessibilityTrusted && eventPostingAllowed
    }

    func refresh() {
        accessibilityTrusted = AXIsProcessTrusted()
        eventPostingAllowed = CGPreflightPostEventAccess()
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestPostEventAccess()
        refresh()
    }
}
