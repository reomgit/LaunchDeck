// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

struct LightingSettingsView: View {
    let coordinator: AppCoordinator
    @State private var paintColor: Color = .green

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(coordinator.selectedProfile?.name ?? "Profile") · \(coordinator.selectedPage?.name ?? "Home")").font(.headline)
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Press effect", selection: setting(\.pressEffect)) {
                            ForEach(PressEffect.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Picker("Ambient effect", selection: setting(\.ambientEffect)) {
                            ForEach(AmbientEffect.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        ColorPicker("Effect color", selection: Binding(get: { Color(coordinator.selectedLightingSettings.accentColor) }, set: { color in
                            guard let value = padColor(color) else { return }
                            var settings = coordinator.selectedLightingSettings; settings.accentColor = value
                            coordinator.updatePageLighting(settings)
                        }), supportsOpacity: false)
                        VStack(alignment: .leading) {
                            Text("Brightness · \(Int(coordinator.selectedLightingSettings.brightness * 100))%")
                            Slider(value: setting(\.brightness), in: 0...1)
                        }
                        VStack(alignment: .leading) {
                            Text("Speed · \(coordinator.selectedLightingSettings.speed, specifier: "%.2g")×")
                            Slider(value: setting(\.speed), in: 0.25...3)
                        }
                        Toggle("Execution feedback", isOn: setting(\.showsActionStatus))
                        Toggle("Running-app indicators", isOn: setting(\.showsApplicationStatus))
                        Text("App-launch buttons indicate when their application is running or frontmost.").font(.caption).foregroundStyle(.secondary)
                        Button("Preview Press", systemImage: "sparkles") { coordinator.previewLightingPress() }
                            .disabled(coordinator.isPaused || coordinator.isSessionSuspended)
                        Text("Select a pad in the editor to preview its animation.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LED Pixel Art").font(.headline)
                        pixelCanvas
                        ColorPicker("Paint color", selection: $paintColor, supportsOpacity: false)
                        Button("Import PNG or JPEG…", systemImage: "photo") { coordinator.chooseGridArtwork() }
                        HStack {
                            Button("Fill") {
                                guard let color = padColor(paintColor) else { return }
                                var settings = coordinator.selectedLightingSettings
                                settings.gridArtwork = Array(repeating: color, count: 64)
                                coordinator.updatePageLighting(settings)
                            }
                            Button("Clear Art") {
                                var settings = coordinator.selectedLightingSettings; settings.gridArtwork = nil
                                coordinator.updatePageLighting(settings)
                            }.disabled(coordinator.selectedLightingSettings.gridArtwork == nil)
                        }
                        Text("Colors apply to this page's grid. Disabled pads stay dark. Images are cropped to a centered square.").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: 230)
                }
                if coordinator.selectedLightingSettings.ambientEffect == .audioMeter || coordinator.lighting.audio.isEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Audio-Reactive Lighting").font(.headline)
                        Text("Uses microphone loudness. Audio is not saved. Microphone access is off at launch and starts only when you enable it here.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(coordinator.lighting.audio.isEnabled ? "Disable Microphone" : "Enable Microphone") {
                                if coordinator.lighting.audio.isEnabled { coordinator.lighting.audio.disable() }
                                else { Task { await coordinator.lighting.audio.enable() } }
                            }
                            Text(coordinator.lighting.audio.statusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: coordinator.lighting.audio.level, total: 1).accessibilityLabel("Microphone loudness")
                    }
                }
                Divider()
                HStack {
                    if coordinator.selectedProfile?.kind == .application {
                        Button("Inherit Global Lighting") { coordinator.updatePageLighting(nil) }
                    }
                    Spacer()
                    Button("Reset Page Lighting") { coordinator.updatePageLighting(LightingSettings()) }
                }
            }.padding(20)
        }.onAppear { coordinator.startLightingPreview() }
    }

    private var pixelCanvas: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<8, id: \.self) { row in
                GridRow {
                    ForEach(0..<8, id: \.self) { column in
                        let index = (7 - row) * 8 + column
                        let color = coordinator.selectedLightingSettings.gridArtwork?[safe: index]
                            ?? coordinator.displayedBinding(at: index)?.effectiveColor ?? .off
                        Button {
                            if let color = padColor(paintColor) { coordinator.paintGridPixel(index: index, color: color) }
                        } label: {
                            RoundedRectangle(cornerRadius: 3).fill(Color(color)).frame(width: 24, height: 24)
                                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.2)) }.contentShape(.rect)
                        }.buttonStyle(.plain).accessibilityLabel("LED pixel \(index + 1)")
                    }
                }
            }
        }.padding(6).background(.black, in: .rect(cornerRadius: 8))
    }
    private func setting<Value>(_ keyPath: WritableKeyPath<LightingSettings, Value>) -> Binding<Value> {
        Binding(get: { coordinator.selectedLightingSettings[keyPath: keyPath] }, set: { value in
            var settings = coordinator.selectedLightingSettings; settings[keyPath: keyPath] = value
            coordinator.updatePageLighting(settings)
        })
    }
    private func padColor(_ color: Color) -> PadColor? {
        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
        return PadColor(red: Int((rgb.redComponent * 127).rounded()), green: Int((rgb.greenComponent * 127).rounded()), blue: Int((rgb.blueComponent * 127).rounded()))
    }
}
