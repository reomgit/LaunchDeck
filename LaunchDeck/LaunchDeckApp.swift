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
    @NSApplicationDelegateAdaptor(LaunchDeckAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("LaunchDeck", systemImage: appDelegate.coordinator.isPaused ? "pause.circle" : "square.grid.3x3.fill") {
            MenuBarContent(
                coordinator: appDelegate.coordinator,
                showEditor: appDelegate.showEditor,
                showAbout: appDelegate.showAbout
            )
        }
    }
}

@MainActor
private final class LaunchDeckAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let coordinator = AppCoordinator()
    private var editorWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        showEditor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showEditor() {
        if let editorWindow {
            activate(editorWindow)
            return
        }

        let window = makeWindow(
            title: "LaunchDeck",
            size: NSSize(width: 1_130, height: 760),
            rootView: ContentView().environment(coordinator)
        )
        editorWindow = window
        activate(window)
    }

    func showAbout() {
        if let aboutWindow {
            activate(aboutWindow)
            return
        }

        let window = makeWindow(
            title: "About LaunchDeck",
            size: NSSize(width: 360, height: 250),
            rootView: AboutLaunchDeckView()
        )
        window.styleMask.remove(.resizable)
        aboutWindow = window
        activate(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window == editorWindow { editorWindow = nil }
        if window == aboutWindow { aboutWindow = nil }
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, rootView: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.setContentSize(size)
        window.minSize = size
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func activate(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MenuBarContent: View {
    let coordinator: AppCoordinator
    let showEditor: () -> Void
    let showAbout: () -> Void

    var body: some View {
        Button("About LaunchDeck") {
            showAbout()
        }
        Button("Open Editor") {
            showEditor()
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
