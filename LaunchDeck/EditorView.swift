// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import CoreTransferable
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LaunchDeckEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.undoManager) private var undoManager

    @State private var showInspector = true
    @State private var showActions = false

    var body: some View {
        HStack(spacing: 0) {
            ProfileSidebar(coordinator: coordinator)
                .frame(width: 174)
            Divider()
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Text(coordinator.selectedProfile?.name ?? "Choose a profile")
                        .font(.title2.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Actions", systemImage: "plus") { showActions.toggle() }
                        .popover(isPresented: $showActions) {
                            ActionLibrary(coordinator: coordinator).frame(width: 300, height: 480)
                        }
                    Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() }
                        .labelStyle(.iconOnly)
                        .help(showInspector ? "Hide inspector" : "Show inspector")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        DeviceWorkflowControls(coordinator: coordinator)
                        DeckManager(coordinator: coordinator)
                    }
                    VStack(spacing: 8) {
                        DeviceWorkflowControls(coordinator: coordinator)
                        DeckManager(coordinator: coordinator)
                    }
                }
                LaunchpadSurface(coordinator: coordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                EditorHeader(coordinator: coordinator)
            }
            .padding(16)
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
            if showInspector {
                Divider()
                PadInspector(coordinator: coordinator).frame(width: 300)
            }
        }
        .frame(minWidth: 920, minHeight: 580)
        .environment(\.appearsActive, true)
        .allowsWindowActivationEvents(true)
        .onAppear { coordinator.setUndoManager(undoManager); coordinator.startLightingPreview() }
        .onDisappear { coordinator.stopLightingPreview() }
    }
}

struct ProfileIcon: View {
    let profile: Profile
    @State private var applicationIcon: NSImage?

    var body: some View {
        Group {
            if profile.isGlobal {
                Image(systemName: "square.grid.3x3.fill")
            } else if profile.kind == .manual {
                Image(systemName: "hand.raised")
            } else if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
            }
        }
        .frame(width: 16, height: 16)
        .onAppear(perform: loadApplicationIcon)
        .onChange(of: profile.applicationBundleIdentifier) { _, _ in
            loadApplicationIcon()
        }
    }

    private func loadApplicationIcon() {
        guard !profile.isGlobal,
              let bundleIdentifier = profile.applicationBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            applicationIcon = nil
            return
        }

        applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}


struct AssignmentPayload: Codable, Transferable {
    let label: String
    let color: PadColor
    let action: BindingAction
    let symbolName: String?
    let artworkID: String?
    let pressEffect: PressEffect?
    init(label: String, color: PadColor, action: BindingAction, symbolName: String? = nil, artworkID: String? = nil, pressEffect: PressEffect? = nil) { self.label = label; self.color = color; self.action = action; self.symbolName = symbolName; self.artworkID = artworkID; self.pressEffect = pressEffect }
    init(binding: PadBinding) { self.init(label: binding.label, color: binding.color, action: binding.action, symbolName: binding.symbolName, artworkID: binding.artworkID, pressEffect: binding.pressEffect) }
    func binding(for index: Int) -> PadBinding { PadBinding(index: index, label: label, color: color, action: action, symbolName: symbolName, artworkID: artworkID, pressEffect: pressEffect) }
    static var transferRepresentation: some TransferRepresentation { CodableRepresentation(contentType: .launchDeckAssignment) }
}

private extension UTType { static let launchDeckAssignment = UTType(exportedAs: "dev.reom.launchdeck.assignment") }

extension Color {
    init(_ color: PadColor) { self.init(red: Double(color.red) / 127, green: Double(color.green) / 127, blue: Double(color.blue) / 127) }
}
