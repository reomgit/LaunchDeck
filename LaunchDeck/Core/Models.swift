// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import Foundation

struct PadColor: Codable, Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: Int, green: Int, blue: Int) {
        self.red = UInt8(clamping: red)
        self.green = UInt8(clamping: green)
        self.blue = UInt8(clamping: blue)
    }

    static let blue = PadColor(red: 30, green: 90, blue: 127)
    static let green = PadColor(red: 24, green: 127, blue: 70)
    static let orange = PadColor(red: 127, green: 66, blue: 10)
    static let amber = PadColor(red: 127, green: 95, blue: 0)
    static let off = PadColor(red: 0, green: 0, blue: 0)

    var highlighted: PadColor {
        PadColor(red: min(Int(red) + 30, 127), green: min(Int(green) + 30, 127), blue: min(Int(blue) + 30, 127))
    }
}

enum ShortcutModifier: String, CaseIterable, Codable, Hashable, Sendable {
    case command
    case option
    case control
    case shift

    var displayName: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

struct Shortcut: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: Set<ShortcutModifier>
    let keyLabel: String

    init(keyCode: UInt16, modifiers: Set<ShortcutModifier> = [], keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    var displayName: String {
        ShortcutModifier.allCases.filter(modifiers.contains).map(\.displayName).joined() + keyLabel.uppercased()
    }

    static let copy = Shortcut(keyCode: 8, modifiers: [.command], keyLabel: "C")
    static let paste = Shortcut(keyCode: 9, modifiers: [.command], keyLabel: "V")
    static let newTab = Shortcut(keyCode: 17, modifiers: [.command], keyLabel: "T")
}

enum MacroStep: Codable, Hashable, Sendable {
    case shortcut(Shortcut)
    case delay(milliseconds: Int)
}

enum BindingAction: Codable, Hashable, Sendable {
    case shortcut(Shortcut)
    case macro([MacroStep])
    case disabled

    var displayName: String {
        switch self {
        case let .shortcut(shortcut): shortcut.displayName
        case let .macro(steps): "Macro · \(steps.count) steps"
        case .disabled: "Disabled"
        }
    }
}

struct PadBinding: Codable, Hashable, Identifiable, Sendable {
    var id: Int { index }
    let index: Int
    var label: String
    var color: PadColor
    var action: BindingAction

    init(index: Int, label: String, color: PadColor, action: BindingAction) {
        precondition((0..<64).contains(index), "Pad index must be in 0...63")
        self.index = index
        self.label = label
        self.color = color
        self.action = action
    }
}

struct Profile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var applicationBundleIdentifier: String?
    var bindings: [PadBinding]

    init(id: UUID = UUID(), name: String, applicationBundleIdentifier: String?, bindings: [PadBinding] = []) {
        self.id = id
        self.name = name
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.bindings = bindings
    }

    var isGlobal: Bool { applicationBundleIdentifier == nil }
}

struct Configuration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var profiles: [Profile]
    var selectedDeviceUniqueID: Int32?

    init(schemaVersion: Int = Configuration.currentSchemaVersion, profiles: [Profile], selectedDeviceUniqueID: Int32? = nil) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.selectedDeviceUniqueID = selectedDeviceUniqueID
    }

    static let `default` = Configuration(profiles: [Profile(name: "Global", applicationBundleIdentifier: nil)])
}

struct ResolvedPad: Hashable, Sendable {
    let binding: PadBinding?
    let sourceProfileID: UUID?
    let isDisabled: Bool
}

struct ResolvedLayout: Sendable {
    let revision: Int
    private let pads: [ResolvedPad]

    init(revision: Int, pads: [ResolvedPad]) {
        precondition(pads.count == 64)
        self.revision = revision
        self.pads = pads
    }

    func binding(at index: Int) -> PadBinding? {
        pads[safe: index]?.binding
    }

    func pad(at index: Int) -> ResolvedPad? {
        pads[safe: index]
    }
}

enum PadEventPhase: Sendable, Equatable {
    case pressed
    case released
}

struct PadEvent: Sendable, Equatable {
    let index: Int
    let phase: PadEventPhase
    let generation: Int
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
