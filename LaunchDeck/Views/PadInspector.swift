// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PadInspector: View {
    let coordinator: AppCoordinator
    @State private var resourceError: String?
    var body: some View {
        Group {
            if let index = coordinator.selectedPadIndex {
                let binding = coordinator.displayedBinding(at: index)
                let action = binding?.action ?? .shortcut(.copy)
                Form {
                    Section("Control \(index + 1)") {
                        if coordinator.isInherited(at: index) { Text("Inherited from Global; editing creates an override.").font(.caption).foregroundStyle(.secondary) }
                        if case .disabled = action { Label("Disabled", systemImage: "nosign").foregroundStyle(.secondary) }
                        TextField("Label", text: Binding(get: { binding?.label ?? "" }, set: { coordinator.updateSelectedBinding(label: $0) }))
                        ColorPicker("Color", selection: Binding(get: { Color(binding?.color ?? .blue) }, set: { color in
                            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                            coordinator.updateSelectedBinding(color: PadColor(red: Int((rgb.redComponent * 127).rounded()), green: Int((rgb.greenComponent * 127).rounded()), blue: Int((rgb.blueComponent * 127).rounded())))
                        }), supportsOpacity: false)
                        Picker("Press animation", selection: Binding<PressEffect?>(get: { binding?.pressEffect }, set: coordinator.setSelectedPressEffect)) {
                            Text("Page Default").tag(Optional<PressEffect>.none)
                            ForEach(PressEffect.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                        }.disabled(binding == nil || action == .disabled)
                    }
                    Section("Action") {
                        Menu("Change Action") {
                            Button("Shortcut") { coordinator.updateSelectedBinding(action: .shortcut(.copy)) }
                            Button("Macro") { coordinator.updateSelectedBinding(action: .macro([.shortcut(.copy)])) }
                            Button("Launch Application…") { ResourcePicker.chooseApplication(error: { resourceError = $0 }) { coordinator.updateSelectedBinding(action: .step($0)) } }
                            Button("Open File…") { pickResource(folder: false) }
                            Button("Open Folder…") { pickResource(folder: true) }
                            Button("Website") { coordinator.updateSelectedBinding(action: .step(.openWebsite("https://example.com"))) }
                            Button("Text") { coordinator.updateSelectedBinding(action: .step(.text(""))) }
                            Button("Shell Script") { coordinator.updateSelectedBinding(action: .step(.script(ScriptAction(source: .inline("printf 'Hello\\n'"), language: .shell)))) }
                            Button("AppleScript") { coordinator.updateSelectedBinding(action: .step(.script(ScriptAction(source: .inline("return \"Hello\""), language: .appleScript)))) }
                            if let registry = coordinator.extensionRegistry { ExtensionActionMenu(registry: registry) { coordinator.updateSelectedBinding(action: .step($0)) } }
                            Button("Disabled") { coordinator.disableSelectedPad() }
                            Divider()
                            Button("Home") { coordinator.updateSelectedBinding(action: .navigation(.home)) }
                            Button("Back") { coordinator.updateSelectedBinding(action: .navigation(.back)) }
                            Button("Previous Page") { coordinator.updateSelectedBinding(action: .navigation(.previousPage)) }
                            Button("Next Page") { coordinator.updateSelectedBinding(action: .navigation(.nextPage)) }
                            ForEach(coordinator.editorFolders) { folder in Button("Open \(folder.name)") { coordinator.updateSelectedBinding(action: .navigation(.openFolder(folder.id))) } }
                        }
                        switch action {
                        case let .shortcut(shortcut): ShortcutField(shortcut: shortcut) { coordinator.updateSelectedBinding(action: .shortcut($0)) }
                        case let .step(step): StepEditor(step: step) { coordinator.updateSelectedBinding(action: .step($0)) }
                        case let .macro(steps): MacroEditor(steps: steps) { coordinator.updateSelectedBinding(action: .macro($0)) }
                        case let .navigation(navigation):
                            Text(navigationTitle(navigation))
                            if case let .openFolder(id) = navigation, !coordinator.editorFolders.contains(where: { $0.id == id }) { Label("Destination folder is missing", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        case .disabled: Text("This control blocks its inherited action.").font(.caption)
                        }
                    }
                    Section {
                        DisclosureGroup("Artwork and Symbol") {
                            TextField("SF Symbol", text: Binding(get: { binding?.symbolName ?? "" }, set: { coordinator.setSelectedSymbol($0.isEmpty ? nil : $0) }))
                            Menu("Choose Symbol") {
                                ForEach(["app", "folder", "doc", "globe", "command", "house", "arrow.backward", "play.fill", "music.note", "star.fill", "text.cursor", "terminal"], id: \.self) { symbol in Button { coordinator.setSelectedSymbol(symbol) } label: { Label(symbol, systemImage: symbol) } }
                                Button("Clear Symbol") { coordinator.setSelectedSymbol(nil) }
                            }
                            Button("Choose PNG or JPEG…") { coordinator.chooseArtwork() }
                            Button("Compose Icon") { coordinator.composeSelectedArtwork() }
                            if binding?.artworkID == nil, let store = coordinator.contentLibrary?.iconPacks, !store.installedIcons.isEmpty { InstalledArtworkPicker(store: store, onSelect: coordinator.setSelectedArtwork) }
                            if let id = binding?.artworkID {
                                ArtworkThumbnail(url: coordinator.artworkURL(for: id), side: 80)
                                if let store = coordinator.contentLibrary?.iconPacks, !store.installedIcons.isEmpty { InstalledArtworkPicker(store: store, onSelect: coordinator.setSelectedArtwork) }
                                Button("Clear Artwork") { coordinator.setSelectedArtwork(nil) }
                            }
                        }
                    }
                    if let resourceError { Text(resourceError).foregroundStyle(.red).font(.caption) }
                    Section { Button("Clear Control", role: .destructive) { coordinator.clearSelectedPad() } }
                }.formStyle(.grouped)
                    .id("\(coordinator.selectedProfileID?.uuidString ?? "none")/\(coordinator.selectedPageID)/\(index)")
            } else {
                ContentUnavailableView("Select a Control", systemImage: "hand.tap", description: Text("Choose a grid pad or outer button to edit its action and appearance."))
            }
        }.padding(12).background(.bar)
    }
    private func navigationTitle(_ action: NavigationAction) -> String {
        switch action { case .home: "Home"; case .back: "Back"; case .previousPage: "Previous Page"; case .nextPage: "Next Page"; case let .openFolder(id): coordinator.editorFolders.first(where: { $0.id == id })?.name ?? "Missing Folder" }
    }
    private func pickResource(folder: Bool) {
        ResourcePicker.choose(folder: folder, error: { resourceError = $0 }) { step in coordinator.updateSelectedBinding(action: .step(step)) }
    }
}

struct ShortcutField: View {
    let shortcut: Shortcut
    let update: (Shortcut) -> Void
    @State private var isCapturing = false
    @State private var session = ShortcutCaptureSession()

    var body: some View {
        Button { isCapturing = true } label: {
            Text(shortcut.displayName)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit shortcut")
        .accessibilityValue(shortcut.displayName)
        .help("Click to record a shortcut")
        .sheet(isPresented: $isCapturing, onDismiss: { session.cancel() }) {
            ShortcutCaptureSheet(shortcut: shortcut, session: session, done: finishCapture, cancel: cancelCapture)
                .onAppear {
                    guard isCapturing, NSApplication.shared.isActive else {
                        cancelCapture()
                        return
                    }
                    session.begin(initialShortcut: shortcut)
                    // A permission prompt can deactivate the app while begin is running.
                    if !isCapturing || !NSApplication.shared.isActive { cancelCapture() }
                }
                .onDisappear { session.cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if isCapturing { cancelCapture() }
        }
        .onDisappear { cancelCapture() }
    }

    private func finishCapture() {
        guard isCapturing, NSApplication.shared.isActive else {
            cancelCapture()
            return
        }
        let capturedShortcut = session.finish()
        isCapturing = false
        if let capturedShortcut { update(capturedShortcut) }
    }

    private func cancelCapture() {
        session.cancel()
        isCapturing = false
    }
}

private struct ShortcutCaptureSheet: View {
    let shortcut: Shortcut
    let session: ShortcutCaptureSession
    let done: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Shortcut").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text("Pending shortcut").font(.caption).foregroundStyle(.secondary)
                Text(session.pendingShortcut?.displayName ?? shortcut.displayName)
                    .font(.title.monospaced())
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            captureStatus
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.state != .capturing)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private var captureStatus: some View {
        switch session.state {
        case .idle:
            Text("Preparing keyboard capture…").foregroundStyle(.secondary)
        case .capturing:
            VStack(alignment: .leading, spacing: 8) {
                Label("Capturing keyboard input", systemImage: "record.circle")
                Text("Press a key with the desired modifiers. Pressing another key replaces the pending shortcut, including Escape and Return. Click Done to save or Cancel to discard.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case let .unavailable(reason):
            VStack(alignment: .leading, spacing: 8) {
                Label("Keyboard capture unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(reason).font(.callout)
                Text("Check LaunchDeck in System Settings → Privacy & Security → Input Monitoring, then close this sheet and try again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct StepEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    let step: MacroStep
    let update: (MacroStep) -> Void
    @State private var pickerError: String?
    var body: some View {
        VStack(alignment: .leading) {
            switch step {
            case let .shortcut(shortcut): ShortcutField(shortcut: shortcut) { update(.shortcut($0)) }
            case let .delay(milliseconds):
                TextField("Delay (ms)", value: Binding(get: { milliseconds }, set: { update(.delay(milliseconds: max(0, $0))) }), format: .number)
            case let .launchApplication(bundleIdentifier):
                TextField("Bundle Identifier", text: Binding(get: { bundleIdentifier }, set: { update(.launchApplication(bundleIdentifier: $0)) }))
                Button("Choose Application…") {
                    ResourcePicker.chooseApplication(error: { pickerError = $0 }, update: update)
                }
            case let .openFile(target):
                Text(target.displayPath).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Choose File…") { ResourcePicker.choose(folder: false, error: { pickerError = $0 }, update: update) }
            case let .openFolder(target):
                Text(target.displayPath).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button("Choose Folder…") { ResourcePicker.choose(folder: true, error: { pickerError = $0 }, update: update) }
            case let .openWebsite(url): WebsiteStepEditor(url: url) { update(.openWebsite($0)) }
            case let .text(text): TextEditor(text: Binding(get: { text }, set: { update(.text($0)) })).frame(minHeight: 65, maxHeight: 120)
            case let .script(script): ScriptStepEditor(script: script) { update(.script($0)) }
            case let .extensionAction(invocation):
                if let registry = coordinator.extensionRegistry {
                    ExtensionInvocationEditor(invocation: Binding(get: { invocation }, set: { update(.extensionAction($0)) }), registry: registry)
                    if let expanded = try? registry.expandSteps([step]) {
                        ForEach(Array(expanded.enumerated()), id: \.offset) { _, recipeStep in
                            if case let .script(script) = recipeStep { ScriptStepEditor(script: script, update: { _ in }, readOnly: true) }
                        }
                    }
                } else { Text("Extension library unavailable.") }
            case let .httpRequest(request): Text("\(request.method) \(request.url)").font(.caption); Text("HTTP actions are configured through extension parameters.").font(.caption)

            }
            if let pickerError { Text(pickerError).font(.caption).foregroundStyle(.red) }
        }
    }
}

@MainActor
enum ResourcePicker {
    static func chooseApplication(error: (String) -> Void = { _ in }, update: (MacroStep) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let id = Bundle(url: url)?.bundleIdentifier else { error("The selected application has no bundle identifier."); return }
        update(.launchApplication(bundleIdentifier: id))
    }

    static func choose(folder: Bool, error: (String) -> Void = { _ in }, update: (MacroStep) -> Void) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = folder; panel.canChooseFiles = !folder; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let target = try FileTarget(url: url); update(folder ? .openFolder(target) : .openFile(target)) } catch let failure { error(failure.localizedDescription) }
    }
}

struct MacroEditor: View {
    @Environment(AppCoordinator.self) private var coordinator
    let steps: [MacroStep]
    let update: ([MacroStep]) -> Void
    @State private var error: String?
    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            VStack(alignment: .leading) {
                HStack {
                    Text("Step \(index + 1)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Up", systemImage: "chevron.up") { var copy = steps; copy.swapAt(index, index - 1); update(copy) }.disabled(index == 0)
                    Button("Down", systemImage: "chevron.down") { var copy = steps; copy.swapAt(index, index + 1); update(copy) }.disabled(index == steps.count - 1)
                    Button("Remove", systemImage: "minus.circle") { var copy = steps; copy.remove(at: index); update(copy) }.disabled(steps.count == 1)
                }.labelStyle(.iconOnly)
                StepEditor(step: step) { replacement in var copy = steps; copy[index] = replacement; update(copy) }
            }
        }
        Menu("Add Step") {
            Button("Shortcut") { update(steps + [.shortcut(.copy)]) }
            Button("Delay") { update(steps + [.delay(milliseconds: 250)]) }
            Button("Launch Application…") { ResourcePicker.chooseApplication(error: { error = $0 }) { update(steps + [$0]) } }
            Button("File…") { ResourcePicker.choose(folder: false, error: { error = $0 }) { update(steps + [$0]) } }
            Button("Folder…") { ResourcePicker.choose(folder: true, error: { error = $0 }) { update(steps + [$0]) } }
            Button("Website") { update(steps + [.openWebsite("https://example.com")]) }
            Button("Text") { update(steps + [.text("")]) }
            Button("Shell Script") { update(steps + [.script(ScriptAction(source: .inline("printf 'Hello\\n'"), language: .shell))]) }
            Button("AppleScript") { update(steps + [.script(ScriptAction(source: .inline("return \"Hello\""), language: .appleScript))]) }
            if let registry = coordinator.extensionRegistry { ExtensionActionMenu(registry: registry) { update(steps + [$0]) } }
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
}

struct WebsiteStepEditor: View {
    let url: String
    let update: (String) -> Void
    @State private var draft: String
    init(url: String, update: @escaping (String) -> Void) {
        self.url = url; self.update = update; _draft = State(initialValue: url)
    }
    private var isValid: Bool {
        guard let candidate = URL(string: draft), ["http", "https"].contains(candidate.scheme?.lowercased() ?? ""), let host = candidate.host, !host.isEmpty else { return false }
        return true
    }
    var body: some View {
        TextField("URL", text: $draft, axis: .vertical).lineLimit(1...4)
            .lineLimit(1...4)
            .onChange(of: draft) { _, value in if isValid { update(value) } }
            .onChange(of: url) { _, value in if value != draft { draft = value } }
        if !isValid { Text("Enter a complete HTTP or HTTPS URL. The previous URL remains saved until this is valid.").font(.caption).foregroundStyle(.orange) }
    }
}
