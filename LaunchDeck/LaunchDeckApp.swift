// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka
//
//  LaunchDeckApp.swift
//  LaunchDeck
//
//  Created by Reom Nagasaka on 2026/09/26.
//

import AppKit
import SwiftUI

@main
struct LaunchDeckApp: App {
    @State private var coordinator = AppCoordinator()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Window("LaunchDeck", id: "editor") {
            ContentView()
                .environment(coordinator)
                .task { coordinator.start() }
        }
        .defaultSize(width: 1_130, height: 760)

        Window("About LaunchDeck", id: "about") {
            AboutLaunchDeckView()
        }
        .defaultSize(width: 360, height: 250)
        .windowResizability(.contentSize)

        MenuBarExtra("LaunchDeck", systemImage: coordinator.isPaused ? "pause.circle" : "square.grid.3x3.fill") {
            MenuBarContent(coordinator: coordinator)
        }
    }
}

private struct MenuBarContent: View {
    let coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About LaunchDeck") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "about")
        }
        Button("Open Editor") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "editor")
        }
        Toggle("Pause", isOn: Binding(get: { coordinator.isPaused }, set: { coordinator.isPaused = $0 }))
        Divider()
        Text(coordinator.statusText).foregroundStyle(.secondary)
        Button("Quit LaunchDeck") {
            coordinator.shutdown()
            NSApp.terminate(nil)
        }
    }
}

private struct AboutLaunchDeckView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("LaunchDeck").font(.title2.weight(.semibold))
            Text("A native app-aware Launchpad controller for macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Copyright © 2026 Reom Nagasaka")
                .font(.footnote)
            Text("Licensed under GNU GPL v3.0 only.")
                .font(.footnote)
            Link("View GPL-3.0 license", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.en.html")!)
                .font(.footnote)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
