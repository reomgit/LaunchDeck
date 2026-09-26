// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

enum ActionPlanner {
    static func steps(for action: BindingAction) -> [MacroStep] {
        switch action {
        case let .shortcut(shortcut):
            [.shortcut(shortcut)]
        case let .macro(steps):
            steps
        case .disabled:
            []
        }
    }
}
