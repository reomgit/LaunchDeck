// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct LaunchpadSurface: View {
    let coordinator: AppCoordinator
    private var descriptor: DeviceDescriptor { coordinator.editorModel.descriptor }

    var body: some View {
        let descriptor = descriptor
        let controls = Dictionary(uniqueKeysWithValues: descriptor.controls.map { ("\($0.row):\($0.column)", $0) })
        let rowValues = descriptor.controls.map(\.row)
        let columnValues = descriptor.controls.map(\.column)
        let rows = Array((rowValues.min() ?? 0)...(rowValues.max() ?? 0))
        let columns = Array((columnValues.min() ?? 0)...(columnValues.max() ?? 0))
        GeometryReader { geometry in
            let layout = DeckSurfaceGeometry(viewport: geometry.size, rows: rows.count, columns: columns.count)
            ScrollView([.horizontal, .vertical]) {
                GlassEffectContainer(spacing: 0) {
                    Grid(horizontalSpacing: DeckSurfaceGeometry.spacing, verticalSpacing: DeckSurfaceGeometry.spacing) {
                        ForEach(rows, id: \.self) { row in
                            GridRow {
                                ForEach(columns, id: \.self) { column in
                                    if let control = controls["\(row):\(column)"] {
                                        cell(control, side: layout.cellSide).frame(width: layout.cellSide, height: layout.cellSide)
                                    } else if row == 0 && column == 9 && coordinator.editorModel != .virtual {
                                        SurfaceCorner().frame(width: layout.cellSide, height: layout.cellSide)
                                    } else {
                                        Color.clear.frame(width: layout.cellSide, height: layout.cellSide)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(DeckSurfaceGeometry.padding)
                .background {
                    RoundedRectangle(cornerRadius: 17).fill(.black)
                        .glassEffect(.regular.tint(.black), in: .rect(cornerRadius: 17))
                }
                .frame(width: max(geometry.size.width, layout.boardSize.width), height: max(geometry.size.height, layout.boardSize.height))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(descriptor.name + " surface")
    }
    private func cell(_ control: DeviceControl, side: CGFloat) -> some View {
        PadCell(
            index: control.index,
            side: side,
            unassignedLabel: control.isGrid ? "" : visualLabel(control),
            accessibilityName: control.name,
            binding: coordinator.displayedBinding(at: control.index),
            inherited: coordinator.isInherited(at: control.index),
            selected: coordinator.selectedPadIndex == control.index,
            previewColor: coordinator.lighting.previewColors[control.index],
            style: control.isGrid ? .pad : .control,
            onSelect: { coordinator.selectPad(control.index) },
            onAssign: { coordinator.assign($0.binding(for: control.index), to: control.index) },
            onClear: { coordinator.selectPad(control.index); coordinator.clearSelectedPad() },
            onDisable: { coordinator.selectPad(control.index); coordinator.disableSelectedPad() }
        )
    }
    private func visualLabel(_ control: DeviceControl) -> String {
        switch control.name {
        case "Up": "▲"
        case "Down": "▼"
        case "Left": "◀"
        case "Right": "▶"
        case "Stop / Solo / Mute": "Stop\nSolo\nMute"
        default: control.name.hasPrefix("Scene ") ? "▶" : control.name
        }
    }
}

private struct SurfaceCorner: View {
    var body: some View {
        NovationMark()
            .fill(Color(red: 0.08, green: 0.09, blue: 0.09))
            .padding(11)
            .glassEffect(.regular.tint(Color(red: 0.80, green: 0.81, blue: 0.82)), in: .rect(cornerRadius: 5))
            .accessibilityLabel("Novation logo")
            .accessibilityHidden(true)
    }
}

private struct NovationMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.midY))
        path.closeSubpath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PadCell: View {
    let index: Int
    let side: CGFloat
    var unassignedLabel = ""
    var accessibilityName: String? = nil
    @Environment(AppCoordinator.self) private var coordinator
    let binding: PadBinding?
    let inherited: Bool
    let selected: Bool
    var previewColor: PadColor?
    var style: PadCellStyle = .pad
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
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: style == .pad ? 7 : 6)
                        .strokeBorder(Color.blue, lineWidth: 2.5)
                        .padding(-2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                Button("Clear Control", action: onClear)
                Button("Disable In This Profile", action: onDisable)
            }
    }

    private var visual: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                if let artwork = binding?.artworkID {
                    ArtworkThumbnail(url: coordinator.artworkURL(for: artwork), side: min(24, side * 0.32))
                } else if let symbol = binding?.symbolName {
                    Image(systemName: symbol).font(.system(size: min(19, side * 0.32)))
                }
                if binding != nil || !unassignedLabel.isEmpty {
                    Text(binding?.label ?? unassignedLabel)
                        .lineLimit(binding == nil ? 3 : side >= 86 ? 3 : side >= 68 ? 2 : 1)
                        .minimumScaleFactor(0.7)
                        .font(.system(size: side <= 50 ? 10 : 11, weight: style == .pad ? .medium : .semibold))
                }
                if let binding {
                    Text(binding.action.displayName)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .font(.system(size: side <= 50 ? 8 : 9, weight: .medium))
                        .opacity(0.82)
                }
            }
            .frame(width: side - 10, height: side - 10).padding(4)
            .contentShape(.rect)
            .foregroundStyle(foregroundColor)
            .glassEffect(.regular.tint(faceColor), in: .rect(cornerRadius: style == .pad ? 5 : 4))
            .shadow(color: .black.opacity(0.48), radius: 1, x: 0, y: 1)
            .opacity(inherited ? 0.72 : 1)
        }
        .buttonStyle(.plain)
        .aspectRatio(1, contentMode: .fit)
        .help(binding.map { $0.label + " · " + $0.action.displayName } ?? accessibilityName ?? unassignedLabel)
        .accessibilityLabel("\(accessibilityName ?? "Launchpad control \(index + 1)"), \(binding?.label ?? "unassigned")")
        .accessibilityValue(inherited ? "Inherited from Global" : binding?.action.displayName ?? "Unassigned")
    }

    private var faceColor: Color {
        if binding?.action != .disabled, let previewColor, previewColor != .off || binding != nil { return Color(previewColor) }
        if let binding, binding.action != .disabled { return Color(binding.effectiveColor) }
        return style == .pad
            ? Color(red: 0.80, green: 0.81, blue: 0.82)
            : Color(red: 0.09, green: 0.10, blue: 0.11)
    }

    private var foregroundColor: Color {
        let hasEnabledBinding = binding.map { $0.action != .disabled } ?? false
        if hasEnabledBinding || style != .pad { return .white.opacity(hasEnabledBinding ? 1 : 0.68) }
        return Color(red: 0.14, green: 0.15, blue: 0.15)
    }
}

private enum PadCellStyle {
    case pad
    case control
}

private struct DragBindingModifier: ViewModifier {
    let binding: PadBinding?

    @ViewBuilder func body(content: Content) -> some View {
        if let binding { content.draggable(AssignmentPayload(binding: binding)) } else { content }
    }
}

