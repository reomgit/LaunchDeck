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
    case launchApplication(bundleIdentifier: String)
    case openFile(FileTarget)
    case openFolder(FileTarget)
    case openWebsite(String)
    case text(String)
    case script(ScriptAction)
    case extensionAction(ExtensionInvocation)
    case httpRequest(HTTPRequestAction)
    var displayName: String {
        switch self {
        case let .shortcut(shortcut): shortcut.displayName
        case let .delay(milliseconds): "Wait · \(milliseconds) ms"
        case let .launchApplication(bundleIdentifier): "Launch · \(bundleIdentifier)"
        case let .openFile(target): "Open File · \(URL(fileURLWithPath: target.displayPath).lastPathComponent)"
        case let .openFolder(target): "Open Folder · \(URL(fileURLWithPath: target.displayPath).lastPathComponent)"
        case let .openWebsite(url): "Open Website · \(url)"
        case .text: "Type Text"
        case let .script(script): script.displayName
        case let .extensionAction(invocation): "Extension · \(invocation.extensionID) / \(invocation.actionID)"
        case let .httpRequest(request): "HTTP · \(request.method) \(request.url)"
        }
    }
}

enum BindingAction: Codable, Hashable, Sendable {
    case shortcut(Shortcut)
    case macro([MacroStep])
    case disabled
    case step(MacroStep)
    case navigation(NavigationAction)

    var displayName: String {
        switch self {
        case let .shortcut(shortcut): shortcut.displayName
        case let .macro(steps): "Macro · \(steps.count) steps"
        case .disabled: "Disabled"
        case let .step(step): step.displayName
        case let .navigation(navigation): navigation.displayName
        }
    }
}

struct PadBinding: Codable, Hashable, Identifiable, Sendable {
    var id: Int { index }
    let index: Int
    var label: String
    var color: PadColor
    var action: BindingAction
    var symbolName: String?
    var artworkID: String?
    var pressEffect: PressEffect?
    var effectiveColor: PadColor { action == .disabled ? .off : color }

    init(index: Int, label: String, color: PadColor, action: BindingAction, symbolName: String? = nil, artworkID: String? = nil, pressEffect: PressEffect? = nil) {
        precondition((0..<105).contains(index), "Launchpad control index is out of range")
        self.index = index
        self.label = label
        self.color = color
        self.action = action
        self.symbolName = symbolName
        self.artworkID = artworkID
        self.pressEffect = pressEffect
    }
}

enum ProfileKind: String, Codable, Hashable, Sendable { case global, application, manual }
enum NavigationAction: Codable, Hashable, Sendable {
    case openFolder(UUID), back, home, previousPage, nextPage
    var displayName: String {
        switch self {
        case .openFolder: "Open Folder"
        case .back: "Back"
        case .home: "Home"
        case .previousPage: "Previous Page"
        case .nextPage: "Next Page"
        }
    }
}
struct DeckPage: Codable, Hashable, Identifiable, Sendable {
    static let homeID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    var id: UUID
    var name: String
    var folderID: UUID?
    var bindings: [PadBinding]
    var lighting: LightingSettings?
    init(id: UUID = DeckPage.homeID, name: String = "Home", folderID: UUID? = nil, bindings: [PadBinding] = [], lighting: LightingSettings? = nil) {
        self.id = id; self.name = name; self.folderID = folderID; self.bindings = bindings; self.lighting = lighting
    }
}
struct DeckFolder: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var parentFolderID: UUID?
    init(id: UUID = UUID(), name: String, parentFolderID: UUID? = nil) {
        self.id = id; self.name = name; self.parentFolderID = parentFolderID
    }
}
struct FileTarget: Codable, Hashable, Sendable {
    let bookmark: Data
    let displayPath: String
    init(url: URL) throws {
        bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        displayPath = url.path
    }
    func resolvedURL() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw CocoaError(.fileReadNoPermission) }
        return url
    }
}
struct DeckModelLayout: Codable, Hashable, Sendable {
    var pages: [DeckPage]
    var folders: [DeckFolder]
    var pageOrder: [UUID]?
    var folderOrder: [UUID]?
    init(pages: [DeckPage] = [DeckPage()], folders: [DeckFolder] = [], pageOrder: [UUID]? = nil, folderOrder: [UUID]? = nil) {
        self.pages = pages; self.folders = folders; self.pageOrder = pageOrder; self.folderOrder = folderOrder
    }
}
struct Profile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var applicationBundleIdentifier: String?
    var kind: ProfileKind
    var pages: [DeckPage]
    var folders: [DeckFolder]
    var pageOrder: [UUID]?
    var folderOrder: [UUID]?
    private var modelLayouts: [String: DeckModelLayout] = [:]
    var modelOverridesEnabled = false
    var bindings: [PadBinding] {
        get { pages.first(where: { $0.id == DeckPage.homeID })?.bindings ?? [] }
        set {
            if let index = pages.firstIndex(where: { $0.id == DeckPage.homeID }) { pages[index].bindings = newValue }
            else { pages.insert(DeckPage(bindings: newValue), at: 0) }
        }
    }
    init(id: UUID = UUID(), name: String, applicationBundleIdentifier: String? = nil, bindings: [PadBinding] = [], kind: ProfileKind? = nil, pages: [DeckPage]? = nil, folders: [DeckFolder] = [], pageOrder: [UUID]? = nil, folderOrder: [UUID]? = nil) {
        self.id = id; self.name = name; self.applicationBundleIdentifier = applicationBundleIdentifier
        self.kind = kind ?? (applicationBundleIdentifier == nil ? .global : .application)
        self.pages = pages ?? [DeckPage(bindings: bindings)]; self.folders = folders
        self.pageOrder = pageOrder; self.folderOrder = folderOrder
    }
    func layout(for model: DeviceModel) -> DeckModelLayout {
        if modelOverridesEnabled, model != .miniMK3, let layout = modelLayouts[model.rawValue] { return layout }
        var shared = storedLayout(for: .miniMK3)
        for page in shared.pages.indices {
            shared.pages[page].bindings.removeAll { $0.index >= model.descriptor.controlCount }
        }
        return shared
    }
    /// Stored layouts stay intact while shared mappings are active.
    func storedLayout(for model: DeviceModel) -> DeckModelLayout {
        if model == .miniMK3 { return DeckModelLayout(pages: pages, folders: folders, pageOrder: pageOrder, folderOrder: folderOrder) }
        return modelLayouts[model.rawValue] ?? DeckModelLayout()
    }
    func layoutForEditing(_ model: DeviceModel) -> DeckModelLayout {
        modelOverridesEnabled ? layout(for: model) : storedLayout(for: .miniMK3)
    }
    mutating func setLayout(_ layout: DeckModelLayout, for model: DeviceModel) {
        if model == .miniMK3 {
            pages = layout.pages; folders = layout.folders; pageOrder = layout.pageOrder; folderOrder = layout.folderOrder
        } else { modelLayouts[model.rawValue] = layout }
    }
    var storedModels: [DeviceModel] { [.miniMK3] + DeviceModel.allCases.filter { $0 != .miniMK3 && modelLayouts[$0.rawValue] != nil } }
    var isGlobal: Bool { kind == .global }
    private enum CodingKeys: String, CodingKey { case id, name, applicationBundleIdentifier, kind, pages, folders, pageOrder, folderOrder, modelLayouts, modelOverridesEnabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        applicationBundleIdentifier = try c.decodeIfPresent(String.self, forKey: .applicationBundleIdentifier)
        kind = try c.decodeIfPresent(ProfileKind.self, forKey: .kind) ?? (applicationBundleIdentifier == nil ? .global : .application)
        pages = try c.decode([DeckPage].self, forKey: .pages); folders = try c.decode([DeckFolder].self, forKey: .folders)
        pageOrder = try c.decodeIfPresent([UUID].self, forKey: .pageOrder); folderOrder = try c.decodeIfPresent([UUID].self, forKey: .folderOrder)
        modelLayouts = try c.decodeIfPresent([String: DeckModelLayout].self, forKey: .modelLayouts) ?? [:]
        modelOverridesEnabled = try c.decodeIfPresent(Bool.self, forKey: .modelOverridesEnabled) ?? false
        guard modelLayouts.keys.allSatisfy({ DeviceModel(rawValue: $0) != nil && $0 != DeviceModel.miniMK3.rawValue }) else { throw CocoaError(.fileReadCorruptFile) }
    }
}
struct Configuration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3
    var schemaVersion: Int
    var profiles: [Profile]
    var selectedDeviceUniqueID: Int32?
    var manuallyActivatedProfileID: UUID?
    init(schemaVersion: Int = Configuration.currentSchemaVersion, profiles: [Profile], selectedDeviceUniqueID: Int32? = nil, manuallyActivatedProfileID: UUID? = nil) {
        self.schemaVersion = schemaVersion; self.profiles = profiles; self.selectedDeviceUniqueID = selectedDeviceUniqueID; self.manuallyActivatedProfileID = manuallyActivatedProfileID
    }
    static let `default` = Configuration(profiles: [Profile(name: "Global")])
}

struct ResolvedPad: Hashable, Sendable {
    let binding: PadBinding?
    let sourceProfileID: UUID?
    let isDisabled: Bool
}

struct ResolvedLayout: Sendable {
    let revision: Int
    private let pads: [ResolvedPad]
    let model: DeviceModel
    let lighting: LightingSettings
    var controlCount: Int { pads.count }

    init(revision: Int, pads: [ResolvedPad], model: DeviceModel = .miniMK3, lighting: LightingSettings = LightingSettings()) {
        precondition(pads.count == model.descriptor.controlCount)
        self.model = model
        self.revision = revision
        self.pads = pads
        self.lighting = lighting
    }

    func binding(at index: Int) -> PadBinding? {
        pads[safe: index]?.binding
    }

    func pad(at index: Int) -> ResolvedPad? {
        pads[safe: index]
    }

    func hasSameContent(as other: ResolvedLayout) -> Bool {
        model == other.model && lighting == other.lighting && pads == other.pads
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
