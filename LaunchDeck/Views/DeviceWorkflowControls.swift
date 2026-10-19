// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct DeviceWorkflowControls: View {
    @Bindable var coordinator: AppCoordinator
    @State private var copyTarget: DeviceModel = .virtual
    @State private var showCopy = false
    @State private var showOverrideWarning = false
    private var panelWidth: CGFloat { min(680, (NSScreen.main?.visibleFrame.width ?? 1000) - 80) }
    private var panelHeight: CGFloat { min(620, (NSScreen.main?.visibleFrame.height ?? 800) - 120) }
    var body: some View {
        HStack {
            Picker("Preview Model", selection: Binding(get: { coordinator.editorModel }, set: coordinator.selectEditorModel)) {
                ForEach(DeviceModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().frame(minWidth: 130, idealWidth: 170, maxWidth: 200)
            .help(coordinator.followsConnectedDevice ? "Model detected automatically from the selected Launchpad" : "Model preview; shared assignments stay the same")
            Label(coordinator.selectedProfile?.modelOverridesEnabled == true ? "Model layouts" : "Shared", systemImage: coordinator.selectedProfile?.modelOverridesEnabled == true ? "lock.open" : "lock")
                .font(.caption).foregroundStyle(.secondary)
            Menu("Tools") {
                Button("Auto-Detect Model", systemImage: "cable.connector") { coordinator.followConnectedHardware() }
                Picker("View Connected Device", selection: Binding(get: { coordinator.configuration.selectedDeviceUniqueID }, set: coordinator.selectHardware)) {
                    Text("Automatic").tag(Int32?.none)
                    ForEach(coordinator.midi.connectedDevices) { device in Text("\(device.name) · \(device.id)").tag(Optional(device.id)) }
                    if let id = coordinator.configuration.selectedDeviceUniqueID, !coordinator.midi.devices.contains(where: { $0.id == id }) {
                        Text("Saved device (disconnected)").tag(Optional(id))
                    }
                }
                Text("All connected Launchpads remain active")
                Divider()
                Toggle("Model-Specific Layouts", isOn: Binding(get: { coordinator.selectedProfile?.modelOverridesEnabled == true }, set: { enabled in
                    if enabled { showOverrideWarning = true }
                    else { coordinator.setModelOverridesEnabled(false) }
                }))
                Divider()
                Button("Lighting and LED Art…", systemImage: "sparkles") { coordinator.workflowPanel = .lighting }
                Button("Copy Layout…") { copyTarget = coordinator.editorModel == .virtual ? .miniMK3 : .virtual; showCopy = true }
                    .disabled(coordinator.selectedProfile?.modelOverridesEnabled != true)
                Button("Extensions…") { coordinator.workflowPanel = .extensions }
                Button("Community Content…") { coordinator.workflowPanel = .content }
                Button("Phone / Tablet…") { coordinator.workflowPanel = .companion }
            }
        }
        .alert("Enable Model-Specific Layouts?", isPresented: $showOverrideWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Unlock Model Layouts") { coordinator.setModelOverridesEnabled(true) }
        } message: {
            Text("Each model can then have different assignments. Previously saved model layouts will become active; models without a saved layout start with your shared mappings. Turn this setting off to lock model layouts and return to shared mappings. All saved layouts are preserved.")
        }
        .sheet(item: $coordinator.workflowPanel) { panel in
            VStack {
                HStack { Text(panel.rawValue.capitalized).font(.headline); Spacer(); Button("Done") { coordinator.workflowPanel = nil } }.padding()
                switch panel {
                case .extensions:
                    if let registry = coordinator.extensionRegistry { ExtensionsView(registry: registry, checkForUpdates: { coordinator.workflowPanel = .content }) }
                    else { Text(coordinator.feedbackMessage ?? "Extension library unavailable.").padding() }
                case .content:
                    if let service = coordinator.contentLibrary { ContentLibraryView(service: service, importProfile: { try coordinator.importProfile($0) }) }
                    else { Text(coordinator.feedbackMessage ?? "Content library unavailable.").padding() }
                case .companion: CompanionSettingsView(server: coordinator.companion)
                case .lighting: LightingSettingsView(coordinator: coordinator)
                }
            }.frame(width: panelWidth, height: panelHeight)
        }
        .sheet(isPresented: $showCopy) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Copy \(coordinator.editorModel.displayName) Layout").font(.title2)
                Picker("Destination", selection: $copyTarget) {
                    ForEach(DeviceModel.allCases.filter { $0 != coordinator.editorModel }, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("This replaces the destination layout with the effective source pages and folders. Your source layout is preserved. You can undo this change.")
                if let preview = coordinator.copyPreview(to: copyTarget) {
                    Text("\(preview.mappings.count) controls map by physical position. \(preview.unmappedBindings.count) assignments have no destination control.")
                    ScrollView {
                        ForEach(Array(preview.unmappedBindings.enumerated()), id: \.offset) { _, binding in
                            Text("Control \(binding.index + 1): \(binding.label) · \(binding.action.displayName)")
                        }
                    }.frame(maxHeight: 180)
                }
                HStack { Button("Cancel", role: .cancel) { showCopy = false }; Spacer(); Button("Replace Destination Layout") { coordinator.copySelectedLayout(to: copyTarget); showCopy = false } }
            }.padding(24).frame(width: min(520, panelWidth))
        }
    }
}
