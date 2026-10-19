// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentLibraryView: View {
    @ObservedObject var service: ContentLibraryService
    @ObservedObject private var registry: ExtensionRegistry
    @ObservedObject private var icons: IconPackStore
    var importProfile: (Profile) throws -> Void
    @State private var query = ""
    @State private var type: ContentType?
    @State private var model: String?
    @State private var app = ""
    @State private var catalogURL = ""
    @State private var message: String?
    @State private var messageIsError = false
    init(service: ContentLibraryService, importProfile: @escaping (Profile) throws -> Void) {
        self.service = service; registry = service.registry; icons = service.iconPacks; self.importProfile = importProfile
    }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Content Library").font(.title2.bold())
            Text("Install an independent profile, reusable artwork, or integration actions. Starter content works offline.").foregroundStyle(.secondary)
            TextField("HTTPS catalog URL", text: $catalogURL, axis: .vertical).lineLimit(1...4)
            HStack {
                Button("Load Catalog") { Task { do { guard let url = URL(string: catalogURL) else { throw EcosystemError("Enter a valid catalog URL.") }; try await service.fetchCatalog(from: url); message = nil; messageIsError = false } catch { message = error.localizedDescription; messageIsError = true } } }
                    .disabled(service.isLoading)
                Button("Bundled Starter") { do { try service.useBundledCatalog(); message = nil; messageIsError = false } catch { message = error.localizedDescription; messageIsError = true } }
                    .disabled(service.isLoading)
            }
            TextField("Search names, authors, apps, or services", text: $query)
            HStack {
                Picker("Type", selection: $type) {
                    Text("All Types").tag(ContentType?.none)
                    ForEach(ContentType.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }.frame(maxWidth: .infinity)
                Picker("Model", selection: $model) {
                    Text("All Models").tag(String?.none)
                    ForEach(Array(Set(service.entries.flatMap(\.supportedDeviceModels))).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
                }.frame(maxWidth: .infinity)
            }
            TextField("Filter by application bundle identifier (optional)", text: $app, axis: .vertical).lineLimit(1...4)
            if service.isLoading { ProgressView().controlSize(.small) }
            if let message { Text(message).foregroundStyle(messageIsError ? Color.red : Color.secondary).textSelection(.enabled) }
            else if let error = service.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(ContentCatalog(entries: service.entries).filtered(query: query, type: type, model: model, application: app.isEmpty ? nil : app)) { entry in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: symbol(for: entry.type)).font(.title2).frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(.headline)
                                    Text(entry.version).font(.caption).foregroundStyle(.secondary)
                                    Text(entry.description).font(.callout)
                                    Text("\(entry.author) · \(entry.license) · \(entry.type.displayName)").font(.caption).foregroundStyle(.secondary)
                                    if !entry.supportedServices.isEmpty { Text(entry.supportedServices.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                                    if let version = service.installedVersion(for: entry) { Text("Installed \(version)\(service.hasUpdate(entry) ? " · update available" : "")").font(.caption).foregroundStyle(.secondary) }
                                }.fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button(service.hasUpdate(entry) ? "Update" : (service.installedVersion(for: entry) == nil ? "Install" : (entry.type == .profile ? "Import Again" : "Reinstall"))) {
                                Task { do { try await service.install(entry, importProfile: importProfile); message = "Installed \(entry.name)."; messageIsError = false } catch { message = error.localizedDescription; messageIsError = true } }
                            }.disabled(service.isLoading)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }.padding(6)
                    }
                }
            }
            Text("Profiles are imported independently. Scripts require local enabling before execution. Secret values stay in Keychain.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
            .onAppear { catalogURL = service.catalogURL }
    }
    private func symbol(for type: ContentType) -> String { switch type { case .profile: "square.grid.3x3"; case .iconPack: "photo.on.rectangle"; case .extensionPackage: "puzzlepiece.extension" } }
}

struct ExtensionsView: View {
    @ObservedObject var registry: ExtensionRegistry
    var checkForUpdates: (() -> Void)? = nil
    @State private var message: String?
    @State private var secretReference = "home-assistant-authorization"
    @State private var secretValue = ""
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
                Text("Extensions").font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack { installationActions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { installationActions }
            }
            Text("Installed actions can be assigned to a pad or added to a macro. Removing an extension keeps its assignments available for repair by reinstalling.").foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(registry.installedExtensions) { installed in
                GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: installed.manifest.symbolName ?? "puzzlepiece.extension")
                        Text(installed.manifest.name).font(.headline)
                    }
                    Text(installed.manifest.version).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle("Enabled", isOn: Binding(get: { installed.enabled }, set: { value in do { try registry.setEnabled(id: installed.id, enabled: value); message = nil } catch { message = error.localizedDescription } })).toggleStyle(.switch).fixedSize()
                        Button("Remove", role: .destructive) { do { try registry.remove(id: installed.id); message = nil } catch { message = error.localizedDescription } }
                    }
                    Text("\(installed.manifest.author) · \(installed.manifest.license)").font(.caption).foregroundStyle(.secondary)
                    if !installed.manifest.supportedApplications.isEmpty { Text("Apps: " + installed.manifest.supportedApplications.joined(separator: ", ")).font(.caption) }
                    if !installed.manifest.supportedServices.isEmpty { Text("Services: " + installed.manifest.supportedServices.joined(separator: ", ")).font(.caption) }
                    if !installed.manifest.allowedHosts.isEmpty { Text("HTTP hosts: " + installed.manifest.allowedHosts.joined(separator: ", ")).font(.caption) }
                    Text("Actions: " + installed.manifest.actions.map(\.name).joined(separator: ", ")).font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
            }
            GroupBox("Local HTTP Credentials") {
                VStack(alignment: .leading) {
                    Text("Enter a reference and the complete header value, such as Bearer followed by your token. Assign only the reference in action parameters.").font(.caption).foregroundStyle(.secondary)
                        TextField("Secret reference", text: $secretReference, axis: .vertical).lineLimit(1...4)
                        SecureField("Header value", text: $secretValue)
                    ViewThatFits(in: .horizontal) {
                        HStack { credentialActions }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { credentialActions }
                    }
                }.padding(6)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var installationActions: some View {
        if let checkForUpdates { Button("Catalog / Updates", action: checkForUpdates) }
        Button("Install or Update from File") { installFile() }
    }
    @ViewBuilder private var credentialActions: some View {
        Button("Save to Keychain") { do { try SecretStore().save(secretValue, reference: secretReference); secretValue = ""; message = "Saved local credential." } catch { message = error.localizedDescription } }.disabled(secretValue.isEmpty || secretReference.isEmpty)
        Button("Remove Secret") { do { try SecretStore().remove(reference: secretReference); secretValue = ""; message = "Removed local credential." } catch { message = error.localizedDescription } }.disabled(secretReference.isEmpty)
    }
    private func installFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "launchdeckextension") ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try registry.install(from: url); message = "Installed extension." } catch { message = error.localizedDescription }
    }
}

struct ExtensionInvocationEditor: View {
    @Binding var invocation: ExtensionInvocation
    @ObservedObject var registry: ExtensionRegistry
    private var installed: InstalledExtension? { registry.installedExtensions.first { $0.id == invocation.extensionID } }
    private var action: ExtensionAction? { installed?.manifest.actions.first { $0.id == invocation.actionID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Extension", selection: Binding(get: { invocation.extensionID }, set: { id in
                invocation.extensionID = id
                invocation.actionID = registry.installedExtensions.first { $0.id == id }?.manifest.actions.first?.id ?? ""
                invocation.parameters = [:]
            })) {
                if installed == nil { Text(invocation.extensionID.isEmpty ? "Choose Extension" : "Unavailable: \(invocation.extensionID)").tag(invocation.extensionID) }
                ForEach(registry.installedExtensions) { item in Text(item.manifest.name + (item.enabled ? "" : " (disabled)")).tag(item.id) }
            }
            if let installed {
                Picker("Action", selection: Binding(get: { invocation.actionID }, set: { invocation.actionID = $0; invocation.parameters = [:] })) {
                    if action == nil { Text("Unavailable: \(invocation.actionID)").tag(invocation.actionID) }
                    ForEach(installed.manifest.actions) { Text($0.name).tag($0.id) }
                }
                if !installed.enabled { Text("Enable this extension in Extensions to run it.").font(.caption).foregroundStyle(.orange) }
            } else { Text("Install this extension in Extensions to repair the assignment.").font(.caption).foregroundStyle(.orange) }
            if let action {
                ForEach(action.parameters) { parameter in
                    if parameter.type == .choice {
                        Picker(parameter.name, selection: valueBinding(parameter)) { Text("Choose Value").tag(""); ForEach(parameter.choices, id: \.self) { Text($0).tag($0) } }
                    } else if parameter.type == .boolean {
                        Picker(parameter.name, selection: valueBinding(parameter)) { Text("Choose Value").tag(""); Text("True").tag("true"); Text("False").tag("false") }
                    } else {
                        TextField(parameter.name + (parameter.required ? " *" : ""), text: valueBinding(parameter), axis: .vertical).lineLimit(1...4)
                        if parameter.type == .secretReference { Text("Local Keychain reference; configure its value in Extensions.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private func valueBinding(_ parameter: ExtensionParameter) -> Binding<String> {
        Binding(get: { invocation.parameters[parameter.id] ?? parameter.defaultValue ?? "" }, set: { invocation.parameters[parameter.id] = $0 })
    }
}

struct InstalledArtworkPicker: View {
    @ObservedObject var store: IconPackStore
    var onSelect: (String) -> Void
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) {
                ForEach(store.installedIcons) { icon in
                    Button { onSelect(icon.artworkID) } label: {
                        VStack {
                            ArtworkThumbnail(url: ProfilePackageStore(directory: store.directory).artworkURL(for: icon.artworkID), side: 54)
                            Text(icon.name).font(.caption).lineLimit(2)
                        }.frame(width: 84, height: 84)
                    }.buttonStyle(.bordered)
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 160, maxHeight: 240)
    }
}
