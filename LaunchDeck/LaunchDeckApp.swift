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
            size: NSSize(width: 1_280, height: 860),
            rootView: ContentView().environment(coordinator)
        )
        installTitlebarControls(on: window)
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
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let preferred = window.frameRect(forContentRect: CGRect(origin: .zero, size: size)).size
        window.setFrame(EditorWindowGeometry.initialFrame(visibleFrame: visible, preferredSize: preferred), display: false)
        window.contentMinSize = title == "LaunchDeck" ? NSSize(width: min(920, visible.width - 32), height: min(580, visible.height - 64)) : size
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func installTitlebarControls(on window: NSWindow) {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.automaticallyAdjustsSize = false

        let hostingView = NSHostingView(rootView: TitlebarStatusControls(coordinator: coordinator))
        hostingView.sizingOptions = []
        hostingView.setFrameSize(NSSize(width: 176, height: 30))
        accessory.view = hostingView

        window.addTitlebarAccessoryViewController(accessory)
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
        Button("Extensions…") { showEditor(); coordinator.workflowPanel = .extensions }
        Button("Community Content…") { showEditor(); coordinator.workflowPanel = .content }
        Button("Phone / Tablet…") { showEditor(); coordinator.workflowPanel = .companion }
        if !coordinator.permissions.canPostEvents {
            Button("Grant Keyboard Access…") {
                coordinator.permissions.requestAccess()
            }
        }
        Toggle("Pause", isOn: Binding(get: { coordinator.isPaused }, set: { coordinator.isPaused = $0 }))
        Divider()
        Text(coordinator.runtimeDescription)
        Menu("Advanced") {
            ProfileOverrideMenu(coordinator: coordinator)
        }
        if let error = coordinator.persistenceError { Text(error).foregroundStyle(.red) }
        if let feedback = coordinator.feedbackMessage { Text(feedback) }
        Divider()
        Text(coordinator.statusText).foregroundStyle(.secondary)
        Button("Quit LaunchDeck") {
            coordinator.shutdown()
            NSApp.terminate(nil)
        }
    }
}

private struct TitlebarStatusControls: View {
    @Bindable var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: coordinator.midi.connectionName == nil ? "cable.connector.slash" : "cable.connector")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel(coordinator.midi.connectionName.map { "Connected to \($0)" } ?? "No Launchpad connected")
                .help(coordinator.midi.connectionName.map { "Connected to \($0)" } ?? "No Launchpad connected")

            Image(systemName: coordinator.permissions.canPostEvents ? "checkmark.shield" : "lock.shield")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel(coordinator.permissions.canPostEvents ? "Keyboard access ready" : "Keyboard access required")
                .help(coordinator.permissions.canPostEvents ? "Keyboard access ready" : PermissionService.settingsGuidance)

            Toggle("Pause", isOn: $coordinator.isPaused)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(coordinator.isPaused ? "Paused · switch off to resume" : "Running · switch on to pause")
        }
        .padding(.horizontal, 10)
        .frame(width: 176, height: 30, alignment: .trailing)
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
