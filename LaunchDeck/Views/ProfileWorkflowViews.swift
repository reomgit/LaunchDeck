// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct ProfileSidebar: View {
    @Bindable var coordinator: AppCoordinator
    @State private var rename = ""
    @State private var showingRename = false
    var body: some View {
        List(selection: $coordinator.selectedProfileID) {
            ForEach(coordinator.configuration.profiles) { profile in
                Label { Text(profile.name) } icon: { ProfileIcon(profile: profile) }
                    .tag(profile.id)
            }
        }
        .onChange(of: coordinator.selectedProfileID) { _, id in coordinator.selectProfile(id) }
        .safeAreaInset(edge: .bottom) {
            Menu("Profiles", systemImage: "plus") {
                    Button("New Manual Profile") { coordinator.addManualProfile() }
                    Button("Choose Application…") { coordinator.chooseApplicationProfile() }
                    Divider()
                    Button("Rename…") { rename = coordinator.selectedProfile?.name ?? ""; showingRename = true }.disabled(coordinator.selectedProfile?.isGlobal != false)
                    Button("Duplicate as Manual") { coordinator.duplicateSelectedProfile() }
                    Button("Delete", role: .destructive) { coordinator.removeSelectedProfile() }.disabled(coordinator.selectedProfile?.isGlobal != false)
                    Divider()
                    Button("Import Profile…") { coordinator.importProfile() }
                    Button("Export Profile…") { coordinator.exportSelectedProfile() }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .alert("Rename Profile", isPresented: $showingRename) {
            TextField("Name", text: $rename)
            Button("Save") { coordinator.renameSelectedProfile(rename) }
            Button("Cancel", role: .cancel) { }
        }
    }
}

struct EditorHeader: View {
    let coordinator: AppCoordinator
    @State private var showMessage = false
    private var message: String? { coordinator.persistenceError ?? coordinator.feedbackMessage }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editing: \(coordinator.selectedProfile?.name ?? "Choose a profile")").font(.caption)
                    Text(coordinator.runtimeDescription).font(.caption).lineLimit(2)
                        .help(coordinator.runtimeDescription)
                    Text("Physical buttons select controls while this window is focused. Navigation buttons still navigate.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(coordinator.statusText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .help(coordinator.statusText)
                }
                Spacer(minLength: 4)
                if !coordinator.permissions.canPostEvents {
                    Button("Keyboard Access", systemImage: "lock.shield") { coordinator.permissions.requestAccess() }
                        .labelStyle(.iconOnly)
                        .help("\(PermissionService.settingsGuidance) Required for shortcuts and text.")
                }
            }
            if let message {
                HStack(alignment: .center, spacing: 8) {
                    Button { showMessage = true } label: {
                        Label(message, systemImage: coordinator.persistenceError == nil ? "info.circle" : "exclamationmark.triangle")
                            .font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if coordinator.feedbackMessage != nil {
                        Button("Dismiss", systemImage: "xmark") { coordinator.clearFeedback() }.labelStyle(.iconOnly)
                    }
                }
                .foregroundStyle(coordinator.persistenceError == nil ? Color.secondary : .red)
                .popover(isPresented: $showMessage) {
                    ScrollView { Text(message).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(width: 360, height: 180)
                }
            }
        }
    }
}

struct ProfileOverrideMenu: View {
    let coordinator: AppCoordinator

    var body: some View {
        Menu("Profile Override") {
            Text("Temporary until resumed or LaunchDeck restarts")
            Button("Resume Automatic Switching") { coordinator.useAutoProfiles() }
                .disabled(coordinator.profileOverrideID == nil)
            Divider()
            ForEach(coordinator.configuration.profiles) { profile in
                Button {
                    coordinator.activateProfile(profile.id)
                } label: {
                    if coordinator.profileOverrideID == profile.id {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        }
    }
}

struct DeckManager: View {
    let coordinator: AppCoordinator
    @State private var rename = ""
    @State private var renameID: UUID?
    @State private var renamingFolder = false
    @State private var showRename = false
    var body: some View {
        HStack {
            Picker("Page", selection: Binding(get: { coordinator.selectedPageID }, set: coordinator.selectPage)) {
                ForEach(coordinator.editorPages) { page in Text(path(for: page)).tag(page.id) }
            }
            .labelsHidden().frame(minWidth: 100, maxWidth: .infinity).help("Preview page or folder")
            Menu("Views", systemImage: "rectangle.3.group") {
                Button("New Root Page") { coordinator.createPage() }
                Button("New Root Folder") { coordinator.createFolder() }
                if let page = coordinator.selectedPage {
                    Button("Rename Selected Page…") { renameID = page.id; rename = page.name; renamingFolder = false; showRename = true }
                    Button("Move Page Earlier") { coordinator.movePage(page.id, by: -1) }
                    Button("Move Page Later") { coordinator.movePage(page.id, by: 1) }
                    Button("Delete Selected Page", role: .destructive) { coordinator.deletePage(page.id) }.disabled(!coordinator.canDeleteSelectedPage)
                }
                ForEach(coordinator.editorFolders) { folder in
                    Menu(folderPath(folder.id)) {
                        Button("New Page Here") { coordinator.createPage(folderID: folder.id) }
                        Button("New Subfolder") { coordinator.createFolder(parentFolderID: folder.id) }
                        Button("Rename…") { renameID = folder.id; rename = folder.name; renamingFolder = true; showRename = true }
                        Button("Move Earlier") { coordinator.moveFolder(folder.id, by: -1) }
                        Button("Move Later") { coordinator.moveFolder(folder.id, by: 1) }
                        Button("Delete Folder", role: .destructive) { coordinator.deleteFolder(folder.id) }.disabled(!coordinator.canDeleteFolder(folder.id))
                    }
                }
            }
        }
        .alert("Rename View", isPresented: $showRename) {
            TextField("Name", text: $rename)
            Button("Save") { if let id = renameID { if renamingFolder { coordinator.renameFolder(id, name: rename) } else { coordinator.renamePage(id, name: rename) } } }
            Button("Cancel", role: .cancel) { }
        }
    }
    private func path(for page: DeckPage) -> String { page.folderID.map { folderPath($0) + " / " + page.name } ?? page.name }
    private func folderPath(_ id: UUID) -> String {
        var names: [String] = []; var current: UUID? = id; var seen = Set<UUID>()
        while let value = current, seen.insert(value).inserted, let folder = coordinator.editorFolders.first(where: { $0.id == value }) { names.insert(folder.name, at: 0); current = folder.parentFolderID }
        return names.joined(separator: " / ")
    }
}

struct ActionLibrary: View {
    let coordinator: AppCoordinator
    @State private var applicationStep: MacroStep?
    @State private var fileStep: MacroStep?
    @State private var folderStep: MacroStep?
    @State private var pickerError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Actions").font(.headline)
                Text("Drag onto a control, or select a control and click an action.").font(.caption).foregroundStyle(.secondary)
                Divider()
                template("Shortcut", .shortcut(.copy), "command")
                template("Macro", .macro([.shortcut(.copy), .delay(milliseconds: 100), .shortcut(.paste)]), "list.number")
                if let applicationStep { template("Launch App", .step(applicationStep), "app") }
                Button("Choose App…", systemImage: "app") { ResourcePicker.chooseApplication(error: { pickerError = $0 }) { applicationStep = $0 } }
                if let fileStep { template("File", .step(fileStep), "doc") }
                Button("Choose File…", systemImage: "doc") { ResourcePicker.choose(folder: false, error: { pickerError = $0 }) { fileStep = $0 } }
                if let folderStep { template("Folder", .step(folderStep), "folder") }
                Button("Choose Folder…", systemImage: "folder") { ResourcePicker.choose(folder: true, error: { pickerError = $0 }) { folderStep = $0 } }
                if let pickerError { Text(pickerError).font(.caption).foregroundStyle(.red) }
                template("Website", .step(.openWebsite("https://example.com")), "globe")
                template("Text", .step(.text("")), "text.cursor")
                template("Shell", .step(.script(ScriptAction(source: .inline("printf 'Hello\\n'"), language: .shell))), "terminal")
                template("AppleScript", .step(.script(ScriptAction(source: .inline("return \"Hello\""), language: .appleScript))), "applescript")
                if let registry = coordinator.extensionRegistry { Menu("Extensions") { ExtensionActionMenu(registry: registry) { step in if coordinator.selectedPadIndex != nil { coordinator.updateSelectedBinding(action: .step(step)) } } } }
                template("Home", .navigation(.home), "house")
                template("Back", .navigation(.back), "arrow.backward")
                template("Previous Page", .navigation(.previousPage), "chevron.left")
                template("Next Page", .navigation(.nextPage), "chevron.right")
                ForEach(coordinator.editorFolders) { folder in template(folder.name, .navigation(.openFolder(folder.id)), "folder") }
                template("Disabled", .disabled, "nosign")
            }
        }
        .padding(16)
    }
    private func template(_ label: String, _ action: BindingAction, _ symbol: String) -> some View {
        let payload = AssignmentPayload(label: label, color: action == .disabled ? .off : .blue, action: action, symbolName: symbol)
        return Button {
            if let index = coordinator.selectedPadIndex { coordinator.assign(payload.binding(for: index), to: index) }
        } label: {
            Label(label, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
        .draggable(payload)
    }
}
