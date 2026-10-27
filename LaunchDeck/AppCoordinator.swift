// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AppKit
import Observation
import UniformTypeIdentifiers

enum WorkflowPanel: String, Identifiable {
    case extensions, content, companion, lighting
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppCoordinator {
    private(set) var configuration: Configuration {
        didSet { editorLayoutCache.invalidate() }
    }
    private(set) var activeApplication: ActiveApplication?
    private(set) var activeLayout: ResolvedLayout
    private(set) var profileOverrideID: UUID?
    var selectedProfileID: UUID? { didSet { refreshLightingPreview() } }
    private(set) var editorModel: DeviceModel = .miniMK3
    private(set) var followsConnectedDevice = true
    private(set) var runtimeDeviceModel: DeviceModel = .miniMK3
    var workflowPanel: WorkflowPanel?
    let scriptApprovals: ScriptApprovalStore
    let scriptExecutor: ScriptExecutor
    let extensionRegistry: ExtensionRegistry?
    let contentLibrary: ContentLibraryService?
    let companion = CompanionServer()
    let lighting = DeckLightingController()
    private let companionRenderer: LEDRenderer
    private var companionColors: [Int: PadColor] = [:]
    private var companionRenderedRevision: Int?
    private var companionLightingLayout: ResolvedLayout?
    private var companionLightingPageID: UUID?
    private var companionLightingProfileID: UUID?
    private var companionLightingPaused = false
    private var runningBundleIDs: Set<String> = []
    private var companionNavigation = DeckNavigation()
    private var companionSequence = false
    private var companionFeedback: String?
    var selectedPadIndex: Int?
    private(set) var selectedPageID = DeckPage.homeID { didSet { refreshLightingPreview() } }
    private(set) var feedbackMessage: String?
    private(set) var persistenceError: String?
    private(set) var isSessionSuspended = false
    var isPaused = false {
        didSet {
            if isPaused {
                actionExecutor.cancel(); heldPads.removeAll()
                for session in hardwareSessions.values { session.clearHeldPads() }
            }
            lighting.audio.setSuspended(isPaused || isSessionSuspended)
            resolveRuntimeLayout()
        }
    }
    let permissions = PermissionService()
    let midi = MIDIService()
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let packageStore: ProfilePackageStore
    @ObservationIgnored private let resolver = ProfileResolver()
    @ObservationIgnored private let editorLayoutCache = EditorLayoutCache()
    @ObservationIgnored private let appMonitor: ActiveAppMonitor
    @ObservationIgnored private let actionExecutor: ActionExecutor
    @ObservationIgnored private let sessionMonitor: WorkspaceSessionMonitor
    @ObservationIgnored private let ledRenderer: LEDRenderer
    private var hardwareSessions: [Int32: HardwareDeckSession] = [:]
    private var navigation = DeckNavigation()
    @ObservationIgnored private var runtimeProfileID: UUID?
    @ObservationIgnored private var heldPads = Set<Int>()
    @ObservationIgnored private var nextRevision = 1
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var undoManager: UndoManager?
    @ObservationIgnored private var canPersist = true

    init(profileStore: ProfileStore = ProfileStore(), sessionMonitor: WorkspaceSessionMonitor = WorkspaceSessionMonitor(),
         actionExecutor: ActionExecutor = ActionExecutor(), appMonitor: ActiveAppMonitor = ActiveAppMonitor(),
         companionRenderer: LEDRenderer = LEDRenderer(model: { .virtual }, send: { _ in })) {
        self.companionRenderer = companionRenderer
        self.profileStore = profileStore
        self.appMonitor = appMonitor
        scriptApprovals = ScriptApprovalStore(directory: profileStore.directory)
        scriptExecutor = ScriptExecutor(approvals: scriptApprovals)
        var ecosystemFailure: String?
        var registry: ExtensionRegistry?
        var library: ContentLibraryService?
        do {
            registry = try ExtensionRegistry(directory: profileStore.directory)
            if let registry { library = try ContentLibraryService(directory: profileStore.directory, registry: registry) }
        } catch { ecosystemFailure = "Could not load extensions or content: \(error.localizedDescription) Original files are preserved." }
        extensionRegistry = registry; contentLibrary = library
        self.sessionMonitor = sessionMonitor
        self.actionExecutor = actionExecutor
        packageStore = ProfilePackageStore(directory: profileStore.directory)
        var loaded = Configuration.default
        do { loaded = try profileStore.load() }
        catch {
            let cocoa = error as NSError
            if cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSFileReadNoSuchFileError {
                persistenceError = "Could not load profiles: \(error.localizedDescription) Your original profiles.json is preserved. Restore it and restart LaunchDeck; export any new work before restarting."
                canPersist = false
            }
        }
        // Legacy pins never disable automatic switching after launch. Overrides are session-only.
        loaded.manuallyActivatedProfileID = nil
        configuration = loaded
        selectedProfileID = loaded.profiles.first(where: \.isGlobal)?.id
        let runtime = ProfileResolver().activeProfile(profiles: loaded.profiles, bundleIdentifier: nil)
        runtimeProfileID = runtime?.id
        activeLayout = ProfileResolver().resolve(profiles: loaded.profiles, bundleIdentifier: nil, revision: 0, profileID: runtime?.id)
        ledRenderer = LEDRenderer(midi: midi)
        companionRenderer.onFrame = { [weak self] colors in self?.companionColors = colors }
        lighting.onAudioLevel = { [weak self] level in
            guard let self else { return }
            for session in self.hardwareSessions.values { session.renderer.setAudioLevel(level) }
            if self.companion.isRunning { self.companionRenderer.setAudioLevel(level) }
        }
        feedbackMessage = ecosystemFailure ?? scriptApprovals.errorMessage
        actionExecutor.expandSteps = { [weak self] steps in
            if let registry = self?.extensionRegistry { return try registry.expandSteps(steps) }
            if steps.contains(where: { if case .extensionAction = $0 { return true }; return false }) {
                throw ScriptExecutionFailure("Extensions are unavailable. Check the library load error.")
            }
            return steps
        }
        actionExecutor.performAdditionalStep = { [weak self] step in
            guard let self else { throw CancellationError() }
            switch step {
            case let .script(script): _ = try await self.scriptExecutor.run(script)
            case let .httpRequest(request): try await HTTPActionExecutor().execute(request, secrets: SecretStore())
            default: throw ScriptExecutionFailure("Unsupported additional action.")
            }
        }
        companion.onSnapshot = { [weak self] in self?.companionSnapshot() ?? CompanionSnapshot(revision: 0, profileName: "Unavailable", mode: "Auto", pageID: DeckPage.homeID, pageName: "Home") }
        companion.onPress = { [weak self] index, revision, page in
            guard let self else { return "Desktop unavailable." }
            return self.pressCompanion(index: index, revision: revision, pageID: page)
        }
        companion.onActivate = { [weak self] id in
            guard let self else { return "Desktop unavailable." }
            if let id {
                guard self.configuration.profiles.contains(where: { $0.id == id }) else { return "Profile no longer exists." }
                self.activateProfile(id)
            } else { self.useAutoProfiles() }
            return nil
        }
        companion.onArtwork = { [weak self] id in
            guard let self, self.companionSnapshot().controls.contains(where: { $0.artworkID == id }) else { return nil }
            return try? Data(contentsOf: self.artworkURL(for: id))
        }
        companion.onStop = { [weak self] in
            guard let self else { return }
            if self.companionSequence { self.actionExecutor.cancel() }
            self.companionRenderer.stop(clear: true)
            self.companionColors = [:]; self.companionRenderedRevision = nil
            self.companionLightingLayout = nil
        }
        midi.onPadEvent = { [weak self] event in self?.handle(event) }
        midi.onDevicePadEvent = { [weak self] event in self?.handleDeviceEvent(event) }
        midi.onDevicesChanged = { [weak self] in self?.synchronizeHardwareSessions() }
        midi.onConnectionChanged = { [weak self] _ in self?.synchronizeHardwareSessions() }
        appMonitor.onChange = { [weak self] application in self?.updateActiveApplication(application) }
        appMonitor.onRunningApplicationsChanged = { [weak self] identifiers in
            guard let self else { return }
            self.runningBundleIDs = identifiers
            self.refreshApplicationLighting()
        }
        sessionMonitor.onAvailabilityChanged = { [weak self] available in self?.updateSessionAvailability(available) }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        sessionMonitor.start()
        permissions.refresh(); appMonitor.start()
        midi.selectDevice(configuration.selectedDeviceUniqueID)
        if !isSessionSuspended { midi.start() }
        resolveRuntimeLayout()
    }
    func shutdown() {
        didStart = false
        sessionMonitor.stop()
        companion.stop()
        lighting.shutdown(); companionRenderer.stop(clear: true)
        actionExecutor.cancel(); ledRenderer.render(activeLayout, paused: true)
        for session in hardwareSessions.values { session.renderer.stop(clear: true) }
        midi.stop(); appMonitor.stop()
    }
    var globalProfile: Profile? { configuration.profiles.first(where: \.isGlobal) }
    var selectedProfile: Profile? { configuration.profiles.first { $0.id == selectedProfileID } }
    // Reading these observed inputs on cache hits keeps SwiftUI and undo updates correct.
    private var editorSnapshot: EditorLayoutSnapshot {
        editorLayoutCache.snapshot(configuration: configuration, profileID: selectedProfileID, model: editorModel)
    }
    var editorPages: [DeckPage] { editorSnapshot.pages }
    var editorFolders: [DeckFolder] { editorSnapshot.folders }
    var selectedPage: DeckPage? { editorPages.first { $0.id == selectedPageID } }
    var runtimeProfile: Profile? {
        resolver.activeProfile(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier, manuallyActivatedProfileID: profileOverrideID)
    }
    private var runtimePages: [DeckPage] {
        guard let runtimeProfile else { return [] }
        return resolver.effectivePages(profile: runtimeProfile, global: globalProfile, model: runtimeDeviceModel)
    }
    private var selectedHardwareID: Int32? { midi.selectedDeviceUniqueID ?? midi.connectedDevices.first?.id }
    private var selectedHardwareSession: HardwareDeckSession? { selectedHardwareID.flatMap { hardwareSessions[$0] } }
    var runtimePage: DeckPage? { runtimePages.first { $0.id == (selectedHardwareSession?.pageID ?? navigation.pageID) } }
    var runtimeDescription: String {
        let mode = profileOverrideID == nil ? "Automatic" : "Temporary override"
        let page = runtimePage
        var names = [page?.name ?? "Home"]
        var parent = page?.folderID
        let folders = runtimeProfile.map { resolver.effectiveFolders(profile: $0, global: globalProfile, model: runtimeDeviceModel) } ?? []
        var visited = Set<UUID>()
        while let id = parent, visited.insert(id).inserted, let folder = folders.first(where: { $0.id == id }) {
            names.insert(folder.name, at: 0); parent = folder.parentFolderID
        }
        return "In use: \(runtimeProfile?.name ?? "Global") · \(mode) · \(names.joined(separator: " / "))"
    }
    var statusText: String {
        if isPaused { return "Paused" }
        if isSessionSuspended { return "Suspended · waiting for the active user session" }
        return midi.statusMessage
    }
    func clearFeedback() { feedbackMessage = nil; companionFeedback = nil }
    func setUndoManager(_ manager: UndoManager?) { undoManager = manager }
    func selectProfile(_ id: UUID?) {
        selectedProfileID = id; selectedPageID = DeckPage.homeID; selectedPadIndex = nil
    }
    func selectPage(_ id: UUID) {
        guard editorPages.contains(where: { $0.id == id }) else { return }
        selectedPageID = id; selectedPadIndex = nil
    }
    func selectPad(_ index: Int) {
        guard (0..<editorModel.descriptor.controlCount).contains(index) else { return }
        selectedPadIndex = index
        lighting.previewPress(index: index)
    }
    func selectedProfileBinding(at index: Int) -> PadBinding? { editorSnapshot.rawBinding(at: index, pageID: selectedPageID) }
    func displayedBinding(at index: Int) -> PadBinding? { editorSnapshot.displayedBinding(at: index, pageID: selectedPageID) }
    func isInherited(at index: Int) -> Bool { editorSnapshot.isInherited(at: index, pageID: selectedPageID) }
    func assign(_ binding: PadBinding, to index: Int) {
        replaceSelectedBinding(PadBinding(index: index, label: binding.label, color: binding.color, action: binding.action, symbolName: binding.symbolName, artworkID: binding.artworkID, pressEffect: binding.pressEffect))
    }
    func clearSelectedPad() {
        guard let selectedPadIndex else { return }; replaceSelectedBinding(nil, at: selectedPadIndex)
    }
    func disableSelectedPad() {
        guard let selectedPadIndex else { return }
        replaceSelectedBinding(PadBinding(index: selectedPadIndex, label: "Disabled", color: .off, action: .disabled))
    }
    func updateSelectedBinding(label: String? = nil, color: PadColor? = nil, action: BindingAction? = nil) {
        guard let selectedPadIndex else { return }
        var binding = displayedBinding(at: selectedPadIndex) ?? PadBinding(index: selectedPadIndex, label: "Untitled", color: .blue, action: .shortcut(.copy))
        if let label { binding.label = label }
        if let color { binding.color = color }
        if let action { binding.action = action }
        replaceSelectedBinding(binding)
    }
    func setSelectedSymbol(_ name: String?) {
        guard let index = selectedPadIndex else { return }
        var binding = displayedBinding(at: index) ?? PadBinding(index: index, label: "Untitled", color: .blue, action: .shortcut(.copy))
        binding.symbolName = name?.isEmpty == false ? name : nil
        replaceSelectedBinding(binding)
    }
    func setSelectedArtwork(_ id: String?) {
        guard let index = selectedPadIndex else { return }
        var binding = displayedBinding(at: index) ?? PadBinding(index: index, label: "Untitled", color: .blue, action: .shortcut(.copy))
        binding.artworkID = id; replaceSelectedBinding(binding)
    }
    func artworkURL(for id: String) -> URL { packageStore.artworkURL(for: id) }
    func chooseArtwork() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { setSelectedArtwork(try packageStore.importArtwork(from: url)) }
        catch { feedbackMessage = "Could not import artwork: \(error.localizedDescription)" }
    }
    func composeSelectedArtwork() {
        guard let index = selectedPadIndex, let binding = displayedBinding(at: index),
              let data = ArtworkComposer.render(label: binding.label, symbolName: binding.symbolName, color: binding.color) else {
            feedbackMessage = "Choose a control and label before composing an icon."; return
        }
        do { setSelectedArtwork(try packageStore.importArtwork(data: data, fileExtension: "png")) }
        catch { feedbackMessage = "Could not create icon: \(error.localizedDescription)" }
    }

    func addManualProfile(name: String = "New Profile") {
        editConfiguration("Add Profile") {
            let profile = Profile(name: name, kind: .manual)
            configuration.profiles.append(profile); selectProfile(profile.id)
        }
    }
    func addApplicationProfile(bundleIdentifier: String, name: String) {
        guard !bundleIdentifier.isEmpty, !configuration.profiles.contains(where: { $0.applicationBundleIdentifier == bundleIdentifier }) else { return }
        editConfiguration("Add Application Profile") {
            let profile = Profile(name: name, applicationBundleIdentifier: bundleIdentifier)
            configuration.profiles.append(profile); selectProfile(profile.id)
        }
    }
    func chooseApplicationProfile() {
        let panel = NSOpenPanel(); panel.title = "Choose an Application"; panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        addApplicationProfile(bundleIdentifier: identifier, name: name)
    }
    func renameSelectedProfile(_ name: String) {
        guard let index = selectedProfileIndex, !configuration.profiles[index].isGlobal, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        editConfiguration("Rename Profile") { configuration.profiles[index].name = name }
    }
    func duplicateSelectedProfile() {
        guard let source = selectedProfile else { return }
        editConfiguration("Duplicate Profile") {
            let profile = ConfigurationOperations.materialize(profile: source, global: globalProfile, name: source.name + " Copy")
            configuration.profiles.append(profile); selectProfile(profile.id)
        }
    }
    func removeSelectedProfile() {
        guard let selectedProfile, !selectedProfile.isGlobal else { return }
        editConfiguration("Delete Profile") {
            configuration.profiles.removeAll { $0.id == selectedProfile.id }
            if profileOverrideID == selectedProfile.id { actionExecutor.cancel(); profileOverrideID = nil }
            selectProfile(globalProfile?.id)
        }
    }
    func activateSelectedProfile() { if let id = selectedProfileID { activateProfile(id) } }
    func activateProfile(_ id: UUID) {
        guard configuration.profiles.contains(where: { $0.id == id }) else { return }
        actionExecutor.cancel()
        profileOverrideID = id
        resolveRuntimeLayout()
    }
    func useAutoProfiles() {
        guard profileOverrideID != nil else { return }
        actionExecutor.cancel()
        profileOverrideID = nil
        resolveRuntimeLayout()
    }
    func appCandidates() -> [ActiveApplication] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let identifier = application.bundleIdentifier, identifier != Bundle.main.bundleIdentifier, application.activationPolicy == .regular else { return nil }
            return ActiveApplication(application)
        }.sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    func createPage(name: String = "New Page", folderID: UUID? = nil) {
        guard let index = selectedProfileIndex, folderID == nil || editorFolders.contains(where: { $0.id == folderID }) else { return }
        editConfiguration("Add Page") {
            let page = DeckPage(id: UUID(), name: name, folderID: folderID)
            configuration.profiles[index][layout: editorModel].pages.append(page); selectedPageID = page.id; selectedPadIndex = nil
        }
    }
    func createFolder(name: String = "New Folder", parentFolderID: UUID? = nil) {
        guard let index = selectedProfileIndex, parentFolderID == nil || editorFolders.contains(where: { $0.id == parentFolderID }) else { return }
        editConfiguration("Add Folder") {
            let folder = DeckFolder(name: name, parentFolderID: parentFolderID)
            let page = DeckPage(id: UUID(), name: "Page 1", folderID: folder.id)
            configuration.profiles[index][layout: editorModel].folders.append(folder); configuration.profiles[index][layout: editorModel].pages.append(page)
            selectedPageID = page.id; selectedPadIndex = nil
        }
    }
    func renamePage(_ id: UUID, name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let index = selectedProfileIndex,
              var page = editorPages.first(where: { $0.id == id }) else { return }
        // Metadata edits must keep local overrides, not materialize inherited controls.
        page.bindings = selectedProfile?.layoutForEditing(editorModel).pages.first(where: { $0.id == id })?.bindings ?? []
        page.lighting = selectedProfile?.layoutForEditing(editorModel).pages.first(where: { $0.id == id })?.lighting
        editConfiguration("Rename Page") {
            page.name = name
            if let pageIndex = configuration.profiles[index][layout: editorModel].pages.firstIndex(where: { $0.id == id }) {
                configuration.profiles[index][layout: editorModel].pages[pageIndex] = page
            } else { configuration.profiles[index][layout: editorModel].pages.append(page) }
        }
    }
    func renameFolder(_ id: UUID, name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let index = selectedProfileIndex,
              var folder = editorFolders.first(where: { $0.id == id }) else { return }
        editConfiguration("Rename Folder") {
            folder.name = name
            if let folderIndex = configuration.profiles[index][layout: editorModel].folders.firstIndex(where: { $0.id == id }) {
                configuration.profiles[index][layout: editorModel].folders[folderIndex] = folder
            } else { configuration.profiles[index][layout: editorModel].folders.append(folder) }
        }
    }
    func movePage(_ id: UUID, by offset: Int) {
        guard let profileIndex = selectedProfileIndex else { return }
        var pages = editorPages
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let siblings = pages.indices.filter { pages[$0].folderID == pages[index].folderID }
        guard let position = siblings.firstIndex(of: index), let destination = siblings[safe: position + offset] else { return }
        guard id != DeckPage.homeID, pages[destination].id != DeckPage.homeID else { return }
        pages.swapAt(index, destination)
        editConfiguration("Move Page") {
            configuration.profiles[profileIndex][layout: editorModel].pageOrder = pages.map(\.id)
            if configuration.profiles[profileIndex].kind != .application {
                let stored = configuration.profiles[profileIndex][layout: editorModel].pages
                configuration.profiles[profileIndex][layout: editorModel].pages = pages.compactMap { ordered in stored.first { $0.id == ordered.id } }
            }
        }
    }
    func moveFolder(_ id: UUID, by offset: Int) {
        guard let profileIndex = selectedProfileIndex else { return }
        var folders = editorFolders
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let siblings = folders.indices.filter { folders[$0].parentFolderID == folders[index].parentFolderID }
        guard let position = siblings.firstIndex(of: index), let destination = siblings[safe: position + offset] else { return }
        folders.swapAt(index, destination)
        editConfiguration("Move Folder") {
            configuration.profiles[profileIndex][layout: editorModel].folderOrder = folders.map(\.id)
            if configuration.profiles[profileIndex].kind != .application { configuration.profiles[profileIndex][layout: editorModel].folders = folders }
        }
    }
    var canDeleteSelectedPage: Bool {
        canDeletePage(selectedPageID)
    }
    private func canDeletePage(_ id: UUID) -> Bool {
        guard id != DeckPage.homeID, let page = editorPages.first(where: { $0.id == id }), let selectedProfile,
              selectedProfile.layout(for: editorModel).pages.contains(where: { $0.id == id }) else { return false }
        if selectedProfile.kind == .application, globalProfile?.layout(for: editorModel).pages.contains(where: { $0.id == id }) == true { return false }
        return page.folderID == nil || editorPages.filter { $0.folderID == page.folderID }.count > 1
    }
    func canDeleteFolder(_ id: UUID) -> Bool {
        guard let selectedProfile, selectedProfile.layout(for: editorModel).folders.contains(where: { $0.id == id }) else { return false }
        return selectedProfile.kind != .application || globalProfile?.layout(for: editorModel).folders.contains(where: { $0.id == id }) != true
    }
    func deletePage(_ id: UUID) {
        guard canDeletePage(id), let profileIndex = selectedProfileIndex else { return }
        let isGlobal = selectedProfile?.isGlobal == true
        let shared = selectedProfile?.modelOverridesEnabled != true
        editConfiguration("Delete Page", validating: true) {
            let affected = isGlobal ? configuration.profiles.indices.filter { configuration.profiles[$0].kind != .manual } : [profileIndex]
            for index in affected {
                let models = isGlobal && shared ? configuration.profiles[index].storedModels : [shared ? .miniMK3 : editorModel]
                for model in models {
                    var layout = configuration.profiles[index].storedLayout(for: model)
                    layout.pages.removeAll { $0.id == id }
                    layout.pageOrder?.removeAll { $0 == id }
                    configuration.profiles[index].setLayout(layout, for: model)
                }
            }
            selectedPageID = DeckPage.homeID; selectedPadIndex = nil
        }
    }
    func deleteFolder(_ id: UUID) {
        guard canDeleteFolder(id), let profileIndex = selectedProfileIndex else { return }
        var removed = Set([id])
        var expanded = true
        while expanded {
            let descendants = editorFolders.filter { $0.parentFolderID.map(removed.contains) == true }.map(\.id)
            let oldCount = removed.count; removed.formUnion(descendants); expanded = oldCount != removed.count
        }
        let isGlobal = selectedProfile?.isGlobal == true
        let shared = selectedProfile?.modelOverridesEnabled != true
        let globalRemovedPages = isGlobal ? Set((globalProfile?.layout(for: editorModel).pages ?? []).filter { $0.folderID.map(removed.contains) == true }.map(\.id)) : []
        editConfiguration("Delete Folder", validating: true) {
            let affected = isGlobal ? configuration.profiles.indices.filter { configuration.profiles[$0].kind != .manual } : [profileIndex]
            for index in affected {
                let models = isGlobal && shared ? configuration.profiles[index].storedModels : [shared ? .miniMK3 : editorModel]
                for model in models {
                    var layout = configuration.profiles[index].storedLayout(for: model)
                    let profileFolders = layout.folders
                    var allRemoved = removed
                    var changed = true
                    while changed {
                        let oldCount = allRemoved.count
                        allRemoved.formUnion(profileFolders.filter { $0.parentFolderID.map(allRemoved.contains) == true }.map(\.id))
                        changed = allRemoved.count != oldCount
                    }
                    layout.folders.removeAll { allRemoved.contains($0.id) }
                    layout.folderOrder?.removeAll { allRemoved.contains($0) }
                    let removedPages = Set(layout.pages.filter { $0.folderID.map(allRemoved.contains) == true }.map(\.id))
                    layout.pages.removeAll { $0.folderID.map(allRemoved.contains) == true }
                    layout.pageOrder?.removeAll { removedPages.contains($0) || globalRemovedPages.contains($0) }
                    for pageIndex in layout.pages.indices {
                        layout.pages[pageIndex].bindings.removeAll { binding in
                            if case let .navigation(.openFolder(destination)) = binding.action { return allRemoved.contains(destination) }
                            return false
                        }
                    }
                    configuration.profiles[index].setLayout(layout, for: model)
                }
            }
            selectedPageID = DeckPage.homeID; selectedPadIndex = nil
        }
    }
    func executeNavigation(_ action: NavigationAction) {
        guard let runtimeProfile else { return }
        let changed = selectedHardwareSession.map { $0.navigate(action) }
            ?? navigation.perform(action, pages: runtimePages, folders: resolver.effectiveFolders(profile: runtimeProfile, global: globalProfile, model: runtimeDeviceModel))
        if changed {
            actionExecutor.cancel(); resolveRuntimeLayout()
        } else { feedbackMessage = "Navigation is unavailable here. Check the folder destination or page boundary." }
    }
    func importProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(exportedAs: "dev.reom.launchdeck.profile", conformingTo: .data)]
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try packageStore.importProfile(from: url)
            editConfiguration("Import Profile") { configuration.profiles.append(profile); selectProfile(profile.id) }
            feedbackMessage = "Imported \(profile.name) as an independent profile."
        } catch { feedbackMessage = "Could not import profile: \(error.localizedDescription)" }
    }
    func exportSelectedProfile() {
        guard let selectedProfile else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(exportedAs: "dev.reom.launchdeck.profile", conformingTo: .data)]
        panel.nameFieldStringValue = selectedProfile.name + ".launchdeckprofile"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try packageStore.export(profile: selectedProfile, global: globalProfile, to: url)
            feedbackMessage = "Exported \(selectedProfile.name)."
        } catch { feedbackMessage = "Could not export profile: \(error.localizedDescription)" }
    }

    private var selectedProfileIndex: Int? { configuration.profiles.firstIndex { $0.id == selectedProfileID } }
    private func replaceSelectedBinding(_ binding: PadBinding?, at index: Int? = nil) {
        guard let profileIndex = selectedProfileIndex, let targetIndex = index ?? binding?.index, let page = selectedPage else { return }
        guard configuration.profiles[profileIndex].modelOverridesEnabled || targetIndex < 80 else {
            feedbackMessage = "Enable model-specific layouts to assign controls that only exist on this model."
            return
        }
        editConfiguration(binding == nil ? "Clear Control" : "Edit Control") {
            if !configuration.profiles[profileIndex][layout: editorModel].pages.contains(where: { $0.id == selectedPageID }) {
                configuration.profiles[profileIndex][layout: editorModel].pages.append(DeckPage(id: page.id, name: page.name, folderID: page.folderID))
            }
            guard let pageIndex = configuration.profiles[profileIndex][layout: editorModel].pages.firstIndex(where: { $0.id == selectedPageID }) else { return }
            configuration.profiles[profileIndex][layout: editorModel].pages[pageIndex].bindings.removeAll { $0.index == targetIndex }
            if let binding { configuration.profiles[profileIndex][layout: editorModel].pages[pageIndex].bindings.append(binding) }
        }
    }
    private func editConfiguration(_ name: String, validating: Bool = false, _ mutation: () -> Void) {
        let previous = configuration
        let previousSelection = (selectedProfileID, selectedPageID, selectedPadIndex)
        mutation()
        guard configuration != previous else { return }
        if validating {
            do { try profileStore.validate(configuration) }
            catch {
                configuration = previous
                (selectedProfileID, selectedPageID, selectedPadIndex) = previousSelection
                feedbackMessage = "This view is still referenced by another profile's shared mappings. Enable model-specific layouts for that profile or remove its references first. Your settings are preserved."
                return
            }
        }
        registerUndo(restoring: previous, actionName: name); persistAndRefresh()
    }
    private func registerUndo(restoring restored: Configuration, actionName: String) {
        undoManager?.registerUndo(withTarget: self) { target in target.restore(restored, actionName: actionName) }
        undoManager?.setActionName(actionName)
    }
    private func restore(_ restored: Configuration, actionName: String) {
        let previous = configuration; configuration = restored
        if !configuration.profiles.contains(where: { $0.id == selectedProfileID }) { selectProfile(globalProfile?.id) }
        registerUndo(restoring: previous, actionName: actionName); persistAndRefresh()
    }
    private func persistAndRefresh() {
        if let id = profileOverrideID, !configuration.profiles.contains(where: { $0.id == id }) {
            actionExecutor.cancel(); profileOverrideID = nil
        }
        if !editorPages.contains(where: { $0.id == selectedPageID }) { selectedPageID = DeckPage.homeID; selectedPadIndex = nil }
        // Main-actor serialization keeps rapid edits and Undo writes in chronological order.
        if canPersist {
            do { try profileStore.save(configuration); persistenceError = nil }
            catch { persistenceError = "Could not save profiles: \(error.localizedDescription) Changes remain in memory; retry by editing again or export your profile." }
        }
        if midi.selectedDeviceUniqueID != configuration.selectedDeviceUniqueID { midi.selectDevice(configuration.selectedDeviceUniqueID) }
        resolveRuntimeLayout()
    }
    private func updateActiveApplication(_ application: ActiveApplication?) {
        activeApplication = application
        actionExecutor.activeApplicationChanged(processID: application?.processIdentifier)
        resolveRuntimeLayout()
    }
    private func updateSessionAvailability(_ available: Bool) {
        isSessionSuspended = !available
        lighting.audio.setSuspended(!available || isPaused)
        if !available {
            actionExecutor.cancel()
            heldPads.removeAll()
            ledRenderer.render(activeLayout, paused: true)
            for session in hardwareSessions.values { session.clearHeldPads(); session.renderer.render(session.layout, paused: true) }
            midi.stop()
        } else if didStart {
            permissions.refresh()
            appMonitor.refresh()
            midi.start()
        }
        resolveRuntimeLayout()
    }
    private func resolveRuntimeLayout() {
        let runtime = runtimeProfile
        if runtimeProfileID != runtime?.id {
            navigation.reset(pages: runtimePages); companionNavigation.reset(pages: companionPages); runtimeProfileID = runtime?.id
        }
        else { navigation.reconcile(pages: runtimePages) }
        companionNavigation.reconcile(pages: companionPages)
        nextRevision += 1
        for session in hardwareSessions.values {
            session.update(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
                profileID: runtime?.id, revision: nextRevision, paused: isPaused || isSessionSuspended)
            session.renderer.setAudioLevel(lighting.audio.level)
        }
        activeLayout = selectedHardwareSession?.layout ?? resolver.resolve(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
            revision: nextRevision, profileID: runtime?.id, pageID: navigation.pageID, model: runtimeDeviceModel)
        if hardwareSessions.isEmpty { ledRenderer.render(activeLayout, paused: isPaused || isSessionSuspended) }
        updateCompanionLighting()
        refreshLightingPreview()
        refreshApplicationLighting()
    }
    private func synchronizeHardwareSessions() {
        let valid = Set(midi.connectedDevices.map(\.id))
        let removed = hardwareSessions.keys.filter { !valid.contains($0) }
        if !removed.isEmpty { actionExecutor.cancel() }
        for id in removed { hardwareSessions.removeValue(forKey: id)?.renderer.stop(clear: false) }
        for device in midi.connectedDevices {
            guard let generation = midi.generation(for: device.id) else { continue }
            if let existing = hardwareSessions[device.id], existing.generation == generation, existing.model == device.model { continue }
            if let old = hardwareSessions[device.id] { actionExecutor.cancel(); old.renderer.stop(clear: false) }
            let id = device.id
            hardwareSessions[id] = HardwareDeckSession(deviceID: id, model: device.model, generation: generation,
                send: { [weak self] bytes in
                    guard let self, self.midi.generation(for: id) == generation else { return }
                    self.midi.sendSysEx(bytes, to: id)
                })
        }
        if let model = midi.connectedModel {
            runtimeDeviceModel = model
            if followsConnectedDevice { updateEditorModel(model) }
        }
        resolveRuntimeLayout()
    }
    private func handleDeviceEvent(_ routed: MIDIDeviceEvent) {
        guard let session = hardwareSessions[routed.deviceID],
              midi.generation(for: routed.deviceID) == session.generation,
              session.accept(routed.event), !isPaused, !isSessionSuspended else { return }
        let event = routed.event
        session.renderer.press(index: event.index)
        let binding = session.layout.binding(at: event.index)
        if let binding, case let .navigation(action) = binding.action {
            if session.navigate(action) { actionExecutor.cancel(); resolveRuntimeLayout() }
            return
        }
        if isLaunchDeckFrontmost {
            selectHardware(routed.deviceID)
            updateEditorModel(session.model)
            selectPad(event.index)
            return
        }
        if let binding { executeBinding(binding, index: event.index, fromCompanion: false, deviceID: routed.deviceID) }
    }
    private func handle(_ event: PadEvent) {
        // Live input is handled above with its originating device identity.
        guard selectedHardwareSession == nil else { return }
        guard event.generation == midi.connectionGeneration else { return }
        switch event.phase {
        case .released: heldPads.remove(event.index)
        case .pressed:
            guard heldPads.insert(event.index).inserted else { return }
            guard !isPaused, !isSessionSuspended else { return }
            guard let binding = activeLayout.binding(at: event.index) else {
                if isLaunchDeckFrontmost { selectEditorModel(runtimeDeviceModel); selectPad(event.index) }; return
            }
            if case let .navigation(action) = binding.action { executeNavigation(action); return }
            guard !isLaunchDeckFrontmost else { selectEditorModel(runtimeDeviceModel); selectPad(event.index); return }
            executeBinding(binding, index: event.index, fromCompanion: false)
        }
    }
    func selectEditorModel(_ model: DeviceModel) {
        followsConnectedDevice = false
        updateEditorModel(model)
    }
    private func updateEditorModel(_ model: DeviceModel) {
        guard editorModel != model else { return }
        editorModel = model
        if selectedProfile?.modelOverridesEnabled == true || !editorPages.contains(where: { $0.id == selectedPageID }) {
            selectedPageID = DeckPage.homeID
        }
        if let index = selectedPadIndex, index >= model.descriptor.controlCount { selectedPadIndex = nil }
        refreshLightingPreview()
    }
    func followConnectedHardware() {
        followsConnectedDevice = true
        if let model = midi.connectedModel { updateEditorModel(model) }
    }
    func setModelOverridesEnabled(_ enabled: Bool) {
        guard let index = selectedProfileIndex, configuration.profiles[index].modelOverridesEnabled != enabled else { return }
        var candidate = configuration
        if enabled {
            for model in DeviceModel.allCases where !candidate.profiles[index].storedModels.contains(model) {
                let shared = candidate.profiles[index].layout(for: model)
                candidate.profiles[index].setLayout(shared, for: model)
            }
        }
        candidate.profiles[index].modelOverridesEnabled = enabled
        do { try profileStore.validate(candidate) }
        catch {
            feedbackMessage = "These saved layouts reference folders or pages unavailable in the requested mode. Check the Global profile's model layouts first. Your current settings are preserved."
            return
        }
        actionExecutor.cancel()
        editConfiguration(enabled ? "Enable Model Layouts" : "Use Shared Mappings") {
            configuration = candidate
        }
    }
    func selectHardware(_ id: Int32?) {
        actionExecutor.cancel()
        editConfiguration("Select Device") { configuration.selectedDeviceUniqueID = id }
        midi.selectDevice(id)
        followConnectedHardware()
        synchronizeHardwareSessions()
    }
    func copyPreview(to model: DeviceModel) -> ConfigurationOperations.LayoutCopyPreview? {
        selectedProfile.map { ConfigurationOperations.previewCopy(profile: $0, global: globalProfile, from: editorModel, to: model) }
    }
    func copySelectedLayout(to model: DeviceModel) {
        guard let index = selectedProfileIndex, model != editorModel, configuration.profiles[index].modelOverridesEnabled else { return }
        let global = globalProfile
        editConfiguration("Copy Device Layout") {
            ConfigurationOperations.copyLayout(profile: &configuration.profiles[index], global: global, from: editorModel, to: model)
        }
    }
    func importProfile(_ profile: Profile) throws {
        guard canPersist else { throw ScriptExecutionFailure("Restore the unreadable configuration before importing content.") }
        editConfiguration("Import Profile") { configuration.profiles.append(profile); selectProfile(profile.id) }
        if let persistenceError { throw ScriptExecutionFailure(persistenceError) }
    }
    var selectedLightingSettings: LightingSettings { selectedPage?.lighting ?? LightingSettings() }

    func updatePageLighting(_ settings: LightingSettings?) {
        guard let profileIndex = selectedProfileIndex, let page = selectedPage else { return }
        do { try settings?.validate() }
        catch { feedbackMessage = "Lighting settings are outside the supported range."; return }
        editConfiguration("Edit Page Lighting") {
            var layout = configuration.profiles[profileIndex][layout: editorModel]
            if let index = layout.pages.firstIndex(where: { $0.id == selectedPageID }) {
                layout.pages[index].lighting = settings
            } else {
                layout.pages.append(DeckPage(id: page.id, name: page.name, folderID: page.folderID, lighting: settings))
            }
            configuration.profiles[profileIndex][layout: editorModel] = layout
        }
    }

    func setSelectedPressEffect(_ effect: PressEffect?) {
        guard let index = selectedPadIndex, var binding = displayedBinding(at: index), binding.action != .disabled else { return }
        binding.pressEffect = effect
        replaceSelectedBinding(binding)
    }

    func paintGridPixel(index: Int, color: PadColor) {
        guard (0..<64).contains(index), color.isSevenBit else { return }
        var settings = selectedLightingSettings
        var pixels = settings.gridArtwork ?? (0..<64).map { displayedBinding(at: $0)?.effectiveColor ?? .off }
        pixels[index] = color; settings.gridArtwork = pixels
        updatePageLighting(settings)
    }

    func chooseGridArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let profile = selectedProfileID, page = selectedPageID, model = editorModel
        Task { @MainActor [weak self] in
            do {
                let pixels = try await Task.detached(priority: .userInitiated) {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: 20_000_001) ?? Data()
                    return try LEDGridArtwork.colors(from: data)
                }.value
                guard let self, self.selectedProfileID == profile, self.selectedPageID == page, self.editorModel == model else { return }
                var settings = self.selectedLightingSettings
                settings.gridArtwork = pixels
                self.updatePageLighting(settings)
            } catch { self?.feedbackMessage = "Could not map this image: \(error.localizedDescription)" }
        }
    }

    private func editorLightingLayout() -> ResolvedLayout {
        resolver.resolve(profiles: configuration.profiles, bundleIdentifier: nil, revision: nextRevision,
            profileID: selectedProfileID, pageID: selectedPageID, model: editorModel)
    }
    func startLightingPreview() {
        lighting.startPreview(editorLightingLayout(), paused: isPaused || isSessionSuspended)
        refreshApplicationLighting()
    }
    func stopLightingPreview() { lighting.stopPreview() }
    func previewLightingPress() { lighting.previewPress(index: selectedPadIndex ?? 27) }
    private func refreshLightingPreview() {
        guard lighting.isPreviewing else { return }
        let layout = editorLightingLayout()
        lighting.updatePreview(layout, paused: isPaused || isSessionSuspended)
        lighting.setApplicationStates(LightingStatusResolver.applicationStates(layout: layout, runningBundleIDs: runningBundleIDs, frontmostBundleID: activeApplication?.bundleIdentifier))
    }
    private func refreshApplicationLighting() {
        for session in hardwareSessions.values {
            session.renderer.setApplicationStates(LightingStatusResolver.applicationStates(layout: session.layout, runningBundleIDs: runningBundleIDs, frontmostBundleID: activeApplication?.bundleIdentifier))
        }
        if lighting.isPreviewing {
            lighting.setApplicationStates(LightingStatusResolver.applicationStates(layout: editorLightingLayout(), runningBundleIDs: runningBundleIDs, frontmostBundleID: activeApplication?.bundleIdentifier))
        }
        if companion.isRunning {
            let layout = resolver.resolve(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
                revision: nextRevision, profileID: runtimeProfile?.id, pageID: companionNavigation.pageID, model: .virtual)
            companionRenderer.setApplicationStates(LightingStatusResolver.applicationStates(layout: layout, runningBundleIDs: runningBundleIDs, frontmostBundleID: activeApplication?.bundleIdentifier))
        }
    }
    private func updateCompanionLighting() {
        guard companion.isRunning, companionRenderedRevision != nextRevision else { return }
        let layout = resolver.resolve(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
            revision: nextRevision, profileID: runtimeProfile?.id, pageID: companionNavigation.pageID, model: .virtual)
        companionRenderedRevision = nextRevision
        let paused = isPaused || isSessionSuspended
        let changed = companionLightingLayout?.hasSameContent(as: layout) != true
            || companionLightingPageID != companionNavigation.pageID || companionLightingProfileID != runtimeProfile?.id
            || companionLightingPaused != paused
        guard changed else { return }
        companionLightingLayout = layout; companionLightingPageID = companionNavigation.pageID
        companionLightingProfileID = runtimeProfile?.id; companionLightingPaused = paused
        companionRenderer.render(layout, paused: isPaused || isSessionSuspended)
        companionRenderer.setAudioLevel(lighting.audio.level)
        companionRenderer.setApplicationStates(LightingStatusResolver.applicationStates(layout: layout, runningBundleIDs: runningBundleIDs, frontmostBundleID: activeApplication?.bundleIdentifier))
    }
    private var companionPages: [DeckPage] {
        runtimeProfile.map { resolver.effectivePages(profile: $0, global: globalProfile, model: .virtual) } ?? []
    }
    func companionSnapshot() -> CompanionSnapshot {
        let layout = resolver.resolve(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
            revision: nextRevision, profileID: runtimeProfile?.id, pageID: companionNavigation.pageID, model: .virtual)
        updateCompanionLighting()
        let colors = companion.isRunning ? companionColors : LightingComposer.frame(layout: layout, time: ProcessInfo.processInfo.systemUptime)
        let controls = DeviceModel.virtual.descriptor.controls.map { control in
            let binding = layout.binding(at: control.index)
            let color = isPaused || isSessionSuspended ? .off : (colors[control.index] ?? .off)
            return CompanionControl(index: control.index, row: control.row - 1, column: control.column - 1,
                label: binding?.label ?? "", action: binding.map { companionActionTitle($0.action) } ?? "Unassigned",
                color: String(format: "#%02X%02X%02X", Int(color.red) * 255 / 127, Int(color.green) * 255 / 127, Int(color.blue) * 255 / 127),
                symbolName: binding?.symbolName, artworkID: binding?.artworkID, enabled: binding != nil && !isPaused && !isSessionSuspended)
        }
        return CompanionSnapshot(revision: nextRevision, profileID: runtimeProfile?.id, profileName: runtimeProfile?.name ?? "Global",
            mode: profileOverrideID == nil ? "Auto" : "Manual", pageID: companionNavigation.pageID,
            pageName: companionPages.first(where: { $0.id == companionNavigation.pageID })?.name ?? "Home", controls: controls,
            profiles: configuration.profiles.map { CompanionProfile(id: $0.id, name: $0.name) }, feedback: companionFeedback,
            animated: companion.isRunning && !isPaused && !isSessionSuspended
                && (companionRenderer.isAnimating || (layout.lighting.ambientEffect == .audioMeter && lighting.audio.isCapturing)))
    }
    private func companionActionTitle(_ action: BindingAction) -> String {
        switch action {
        case .shortcut: return "Keyboard Shortcut"
        case let .macro(steps): return "Sequence · \(steps.count) steps"
        case .disabled: return "Disabled"
        case .navigation: return "Navigate"
        case let .step(step):
            switch step {
            case .shortcut: return "Keyboard Shortcut"
            case .delay: return "Delay"
            case .launchApplication: return "Launch Application"
            case .openFile: return "Open File"
            case .openFolder: return "Open Folder"
            case .openWebsite: return "Open Website"
            case .text: return "Enter Text"
            case .script: return "Run Script"
            case .extensionAction: return "Extension Action"
            case .httpRequest: return "HTTP Request"
            }
        }
    }
    func pressCompanion(index: Int, revision: Int, pageID: UUID) -> String? {
        guard !isPaused, !isSessionSuspended else { return "LaunchDeck is paused or the Mac session is unavailable." }
        guard revision == nextRevision, pageID == companionNavigation.pageID else { return "Layout changed. Refresh and try again." }
        guard (0..<64).contains(index) else { return "Unknown control." }
        let layout = resolver.resolve(profiles: configuration.profiles, bundleIdentifier: activeApplication?.bundleIdentifier,
            revision: nextRevision, profileID: runtimeProfile?.id, pageID: pageID, model: .virtual)
        guard let binding = layout.binding(at: index) else { return "This control is unassigned or disabled." }
        companionRenderer.press(index: index)
        if case let .navigation(action) = binding.action {
            guard let runtimeProfile, companionNavigation.perform(action, pages: companionPages,
                folders: resolver.effectiveFolders(profile: runtimeProfile, global: globalProfile, model: .virtual)) else { return "Navigation is unavailable here." }
            actionExecutor.cancel(); resolveRuntimeLayout(); return nil
        }
        if isLaunchDeckFrontmost {
            let steps = (try? actionExecutor.expandSteps(ActionPlanner.steps(for: binding.action))) ?? []
            let hasKeyboard = steps.contains { switch $0 { case .shortcut, .text: true; default: false } }
            let hasLaunch = steps.contains { switch $0 { case .launchApplication, .openFile, .openFolder, .openWebsite: true; default: false } }
            if hasKeyboard && !hasLaunch { return "Switch to the target application on your Mac before using keyboard controls." }
        }
        executeBinding(binding, index: index, fromCompanion: true); return nil
    }
    private func executeBinding(_ binding: PadBinding, index: Int, fromCompanion: Bool, deviceID: Int32? = nil) {
        permissions.refresh()
        let renderer = fromCompanion ? companionRenderer : (deviceID.flatMap { hardwareSessions[$0]?.renderer } ?? ledRenderer)
        let originSession = deviceID.flatMap { hardwareSessions[$0] }
        let originGeneration = originSession?.generation
        let originRevision = fromCompanion ? companionLightingLayout?.revision : (originSession?.layout.revision ?? activeLayout.revision)
        let startsHere = !actionExecutor.isRunning
        if startsHere { companionSequence = fromCompanion; renderer.setStatus(index: index, status: .running) }
        actionExecutor.execute(binding.action, targetProcessID: activeApplication?.processIdentifier, canPostEvents: permissions.canPostEvents) { [weak self] result in
            guard let self else { return }
            if case .rejectedBusy = result { } else { self.companionSequence = false }
            let message: String
            switch result {
            case .dispatched: message = "\(binding.label): dispatched."
            case .rejectedBusy: message = "Another sequence is running. Wait or pause to cancel it."
            case .rejectedPermission: message = "Keyboard access required. \(PermissionService.settingsGuidance)"
            case .cancelled: message = "Sequence cancelled after a target, connection, navigation, pause, or session change."
            case let .failed(reason): message = reason
            }
            self.feedbackMessage = message
            if case .failed = result { self.companionFeedback = "Action failed. Review details on your Mac." }
            else { self.companionFeedback = message }
            let feedbackIsCurrent: Bool
            if fromCompanion {
                feedbackIsCurrent = self.companion.isRunning && self.companionLightingLayout?.revision == originRevision
            } else if let deviceID {
                feedbackIsCurrent = self.hardwareSessions[deviceID]?.generation == originGeneration
                    && self.hardwareSessions[deviceID]?.layout.revision == originRevision
            } else { feedbackIsCurrent = self.hardwareSessions.isEmpty && self.activeLayout.revision == originRevision }
            if startsHere && feedbackIsCurrent {
                switch result {
                case .dispatched: renderer.setStatus(index: index, status: .success)
                case .cancelled: renderer.setStatus(index: index, status: nil)
                case .rejectedBusy: break
                case .failed, .rejectedPermission: renderer.setStatus(index: index, status: .failure)
                }
            }
        }
    }
    private func reportFailure(_ message: String, index: Int) {
        feedbackMessage = message; ledRenderer.flash(index: index, color: .amber)
    }
    private var isLaunchDeckFrontmost: Bool { activeApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
}
