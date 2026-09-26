// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct LaunchDeckEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationSplitView {
            ProfileSidebar(coordinator: coordinator)
        } detail: {
            HSplitView {
                VStack(spacing: 18) {
                    EditorHeader(coordinator: coordinator)
                    ActionLibrary()
                    LaunchpadSurface(coordinator: coordinator)
                }
                .padding(20)
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                PadInspector(coordinator: coordinator)
                    .frame(minWidth: 230, idealWidth: 280, maxWidth: 320)
            }
        }
        .navigationTitle("LaunchDeck")
        .onAppear { coordinator.setUndoManager(undoManager) }
        .toolbar {
            ToolbarItemGroup {
                Label(coordinator.midi.connectionName ?? "No Launchpad", systemImage: coordinator.midi.connectionName == nil ? "cable.connector.slash" : "cable.connector")
                Button(coordinator.permissions.canPostEvents ? "Accessibility Ready" : "Grant Accessibility Access", systemImage: coordinator.permissions.canPostEvents ? "checkmark.shield" : "lock.shield") {
                    coordinator.permissions.requestAccess()
                }
                Toggle("Pause", isOn: $coordinator.isPaused).toggleStyle(.switch)
            }
        }
    }
}

private struct ProfileSidebar: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        List(selection: $coordinator.selectedProfileID) {
            Section("Presets") {
                ForEach(coordinator.configuration.profiles) { profile in
                    Label(profile.name, systemImage: profile.isGlobal ? "square.grid.3x3.fill" : "app.fill").tag(profile.id)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .onChange(of: coordinator.selectedProfileID) { _, selected in coordinator.selectProfile(selected) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Add preset", systemImage: "plus") {
                    Button("Choose Application…", systemImage: "folder.badge.plus") {
                        coordinator.chooseApplicationProfile()
                    }
                    Divider()
                    let candidates = coordinator.appCandidates()
                    if candidates.isEmpty {
                        Text("Open an app to add its preset")
                    } else {
                        ForEach(candidates, id: \.processIdentifier) { application in
                            Button(application.localizedName) {
                                guard let bundleIdentifier = application.bundleIdentifier else { return }
                                coordinator.addApplicationProfile(bundleIdentifier: bundleIdentifier, name: application.localizedName)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct EditorHeader: View {
    let coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(coordinator.selectedProfile?.name ?? "Choose a preset").font(.title2.weight(.semibold))
                Text(coordinator.activeApplication.map { "Runtime: \($0.localizedName)" } ?? "Runtime: Global preset").foregroundStyle(.secondary)
            }
            Spacer()
            Text(coordinator.statusText).font(.footnote).foregroundStyle(coordinator.permissions.canPostEvents ? Color.secondary : Color.orange)
        }
    }
}

private struct ActionLibrary: View {
    var body: some View {
        HStack(spacing: 10) {
            ActionTemplate(label: "Shortcut", subtitle: "⌘C", color: .blue, payload: AssignmentPayload(label: "Shortcut", color: .blue, action: .shortcut(.copy)))
            ActionTemplate(label: "Macro", subtitle: "Steps + delay", color: .orange, payload: AssignmentPayload(label: "Macro", color: .orange, action: .macro([.shortcut(.copy), .delay(milliseconds: 100), .shortcut(.paste)])))
            Spacer()
            Text("Drag an action to a pad").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

private struct ActionTemplate: View {
    let label: String
    let subtitle: String
    let color: PadColor
    let payload: AssignmentPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(color).opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
        .draggable(payload)
        .accessibilityLabel("Drag \(label) action")
    }
}

private struct LaunchpadSurface: View {
    let coordinator: AppCoordinator
    private let spacing: CGFloat = 7
    private let controlSide: CGFloat = 54
    private let topControls = ["Session", "Drums", "Keys", "User", "Mixer", "Volume", "Pan", "Send"]
    private let sideControls = ["Volume", "Pan", "Send A", "Send B", "Stop", "Solo", "Mute", "Record"]

    private var visualPadOrder: [Int] {
        (0..<8).reversed().flatMap { row in
            (0..<8).map { column in row * 8 + column }
        }
    }

    private var gridSide: CGFloat {
        controlSide * 9 + spacing * 8
    }

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            GridRow {
                SurfaceCorner()
                    .frame(width: controlSide, height: controlSide)
                ForEach(Array(topControls.enumerated()), id: \.offset) { index, label in
                    PeripheralControl(label: label, position: .top(index))
                        .frame(width: controlSide, height: controlSide)
                }
            }
            ForEach(0..<8, id: \.self) { row in
                GridRow {
                    ForEach(0..<8, id: \.self) { column in
                        let index = visualPadOrder[row * 8 + column]
                        PadCell(
                            index: index,
                            binding: coordinator.displayedBinding(at: index),
                            inherited: coordinator.isInherited(at: index),
                            selected: coordinator.selectedPadIndex == index,
                            onSelect: { coordinator.selectPad(index) },
                            onAssign: { coordinator.assign($0.binding(for: index), to: index) },
                            onClear: { coordinator.selectPad(index); coordinator.clearSelectedPad() },
                            onDisable: { coordinator.selectPad(index); coordinator.disableSelectedPad() }
                        )
                        .frame(width: controlSide, height: controlSide)
                    }
                    PeripheralControl(label: sideControls[row], position: .side(row))
                        .frame(width: controlSide, height: controlSide)
                }
            }
        }
        .frame(width: gridSide, height: gridSide)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
    }
}

private struct SurfaceCorner: View {
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct PeripheralControl: View {
    enum Position {
        case top(Int)
        case side(Int)
    }

    let label: String
    let position: Position

    var body: some View {
        Button {} label: {
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .aspectRatio(1, contentMode: .fit)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityLabel("\(label) control")
        .accessibilityHint("Peripheral controls are visual-only in this MVP")
    }
}

private struct PadCell: View {
    let index: Int
    let binding: PadBinding?
    let inherited: Bool
    let selected: Bool
    let onSelect: () -> Void
    let onAssign: (AssignmentPayload) -> Void
    let onClear: () -> Void
    let onDisable: () -> Void

    var body: some View {
        visual
            .modifier(DragBindingModifier(binding: binding))
            .dropDestination(for: AssignmentPayload.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                onAssign(payload)
                return true
            }
            .contextMenu {
                Button("Clear Pad", action: onClear)
                Button("Disable In This Preset", action: onDisable)
            }
    }

    private var visual: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                Text(binding?.label ?? "—").lineLimit(1).minimumScaleFactor(0.5).font(.caption.weight(.medium))
                Text(binding?.action.displayName ?? "Unassigned").lineLimit(1).minimumScaleFactor(0.45).font(.caption2).opacity(0.78)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(4)
            .foregroundStyle(.primary)
            .background(Color(binding?.color ?? .off).opacity(binding == nil ? 0.16 : 0.56), in: RoundedRectangle(cornerRadius: 12))
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .white.opacity(inherited ? 0.35 : 0.12), lineWidth: selected ? 3 : 1) }
            .opacity(inherited ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Pad \(index + 1), \(binding?.label ?? "unassigned")")
    }
}

private struct DragBindingModifier: ViewModifier {
    let binding: PadBinding?

    @ViewBuilder func body(content: Content) -> some View {
        if let binding { content.draggable(AssignmentPayload(binding: binding)) } else { content }
    }
}

private struct PadInspector: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        Group {
            if let index = coordinator.selectedPadIndex {
                inspector(for: index)
            } else {
                ContentUnavailableView("Select a Pad", systemImage: "hand.tap", description: Text("Choose a grid cell to set its action and color."))
            }
        }
        .padding(16)
        .background(.bar)
    }

    @ViewBuilder private func inspector(for index: Int) -> some View {
        let localBinding = coordinator.selectedProfileBinding(at: index)
        let action = localBinding?.action ?? .shortcut(.copy)
        let selectedColor = ColorChoice.from(localBinding?.color ?? .blue)
        Form {
            Section("Pad \(index + 1)") {
                if coordinator.isInherited(at: index) { Text("Using Global preset").font(.caption).foregroundStyle(.secondary) }
                TextField("Label", text: Binding(get: { localBinding?.label ?? "" }, set: { coordinator.updateSelectedBinding(label: $0) }))
                Picker("Color", selection: Binding(get: { selectedColor }, set: { coordinator.updateSelectedBinding(color: $0.color) })) {
                    ForEach(ColorChoice.allCases) { choice in Text(choice.title).tag(choice) }
                }
            }
            Section("Action") {
                Picker("Type", selection: Binding(get: { EditorActionKind(action) }, set: { coordinator.updateSelectedBinding(action: $0.action(from: action)) })) {
                    ForEach(EditorActionKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.segmented)
                switch action {
                case let .shortcut(shortcut):
                    ShortcutRecorder(shortcut: Binding(get: { shortcut }, set: { coordinator.updateSelectedBinding(action: .shortcut($0)) }))
                        .frame(height: 30).overlay { Text(shortcut.displayName).font(.body.monospaced()).allowsHitTesting(false) }
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                case let .macro(steps):
                    MacroEditor(steps: steps) { coordinator.updateSelectedBinding(action: .macro($0)) }
                case .disabled:
                    Text("This preset blocks the Global action for this pad.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Clear Pad", role: .destructive) { coordinator.clearSelectedPad() }
                if coordinator.selectedProfile?.isGlobal == false { Button("Disable In This Preset") { coordinator.disableSelectedPad() } }
                if coordinator.selectedProfile?.isGlobal == false { Button("Delete Preset", role: .destructive) { coordinator.removeSelectedProfile() } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct MacroEditor: View {
    let steps: [MacroStep]
    let onUpdate: ([MacroStep]) -> Void

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack {
                Text(step.label).font(.caption)
                Spacer()
                Button("Move Up", systemImage: "chevron.up") {
                    var updated = steps
                    updated.swapAt(index, index - 1)
                    onUpdate(updated)
                }
                .labelStyle(.iconOnly)
                .disabled(index == 0)
                Button("Move Down", systemImage: "chevron.down") {
                    var updated = steps
                    updated.swapAt(index, index + 1)
                    onUpdate(updated)
                }
                .labelStyle(.iconOnly)
                .disabled(index == steps.count - 1)
                Button("Remove", systemImage: "minus.circle") {
                    var updated = steps
                    updated.remove(at: index)
                    onUpdate(updated)
                }.labelStyle(.iconOnly)
            }
        }
        HStack {
            Button("Add Shortcut") { onUpdate(steps + [.shortcut(.copy)]) }
            Button("Add Delay") { onUpdate(steps + [.delay(milliseconds: 250)]) }
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onShortcut = { shortcut in self.shortcut = shortcut }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onShortcut = { shortcut in self.shortcut = shortcut }
    }
}

private final class ShortcutCaptureView: NSView {
    var onShortcut: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard event.keyCode != 53 else { return }
        var modifiers = Set<ShortcutModifier>()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let label = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        onShortcut?(Shortcut(keyCode: event.keyCode, modifiers: modifiers, keyLabel: label))
    }
}

private struct AssignmentPayload: Codable, Transferable {
    let label: String
    let color: PadColor
    let action: BindingAction
    init(label: String, color: PadColor, action: BindingAction) { self.label = label; self.color = color; self.action = action }
    init(binding: PadBinding) { self.init(label: binding.label, color: binding.color, action: binding.action) }
    func binding(for index: Int) -> PadBinding { PadBinding(index: index, label: label, color: color, action: action) }
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .launchDeckAssignment) }
}

private extension UTType { static let launchDeckAssignment = UTType(exportedAs: "dev.reom.launchdeck.assignment") }

private enum EditorActionKind: String, CaseIterable, Identifiable {
    case shortcut, macro, disabled
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    init(_ action: BindingAction) {
        switch action { case .shortcut: self = .shortcut; case .macro: self = .macro; case .disabled: self = .disabled }
    }
    func action(from existing: BindingAction) -> BindingAction {
        switch self {
        case .shortcut: if case let .shortcut(shortcut) = existing { return .shortcut(shortcut) }; return .shortcut(.copy)
        case .macro: if case let .macro(steps) = existing { return .macro(steps) }; return .macro([.shortcut(.copy)])
        case .disabled: return .disabled
        }
    }
}

private enum ColorChoice: String, CaseIterable, Identifiable {
    case blue, green, orange, amber
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: PadColor { switch self { case .blue: .blue; case .green: .green; case .orange: .orange; case .amber: .amber } }
    static func from(_ color: PadColor) -> ColorChoice { allCases.min { lhs, rhs in distance(color, lhs.color) < distance(color, rhs.color) } ?? .blue }
    private static func distance(_ lhs: PadColor, _ rhs: PadColor) -> Int { abs(Int(lhs.red) - Int(rhs.red)) + abs(Int(lhs.green) - Int(rhs.green)) + abs(Int(lhs.blue) - Int(rhs.blue)) }
}

private extension MacroStep {
    var label: String { switch self { case let .shortcut(shortcut): shortcut.displayName; case let .delay(milliseconds): "Wait \(milliseconds) ms" } }
}

private extension Color {
    init(_ color: PadColor) { self.init(red: Double(color.red) / 127, green: Double(color.green) / 127, blue: Double(color.blue) / 127) }
}
