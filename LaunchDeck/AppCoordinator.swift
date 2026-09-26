// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppCoordinator {
    private(set) var configuration: Configuration
    private(set) var activeApplication: ActiveApplication?
    private(set) var activeLayout: ResolvedLayout
    var selectedProfileID: UUID?
    var selectedPadIndex: Int?
    var isPaused = false {
        didSet {
            if isPaused { actionExecutor.cancel() }
            ledRenderer.render(activeLayout, paused: isPaused)
        }
    }

    let permissions = PermissionService()
    let midi = MIDIService()

    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let resolver = ProfileResolver()
    @ObservationIgnored private let appMonitor = ActiveAppMonitor()
    @ObservationIgnored private let actionExecutor = ActionExecutor()
    @ObservationIgnored private let ledRenderer: LEDRenderer
    @ObservationIgnored private var heldPads = Set<Int>()
    @ObservationIgnored private var nextRevision = 1
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var undoManager: UndoManager?

    init(profileStore: ProfileStore = ProfileStore()) {
        self.profileStore = profileStore
        let loaded = (try? profileStore.load()) ?? .default
        configuration = loaded
        selectedProfileID = loaded.profiles.first(where: \.isGlobal)?.id ?? loaded.profiles.first?.id
        activeLayout = ProfileResolver().resolve(profiles: loaded.profiles, bundleIdentifier: nil, revision: 0)
        ledRenderer = LEDRenderer(midi: midi)

        midi.onPadEvent = { [weak self] event in self?.handle(event) }
        midi.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            if connected {
                self.ledRenderer.repaint()
            } else {
                self.heldPads.removeAll()
                self.actionExecutor.cancel()
            }
        }
        appMonitor.onChange = { [weak self] application in self?.updateActiveApplication(application) }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        permissions.refresh()
        appMonitor.start()
        midi.start()
        resolveRuntimeLayout()
    }

    func shutdown() {
        actionExecutor.cancel()
        ledRenderer.render(activeLayout, paused: true)
        midi.stop()
        appMonitor.stop()
    }

    var selectedProfile: Profile? {
        configuration.profiles.first { $0.id == selectedProfileID }
    }

    var statusText: String {
        if isPaused { return "Paused" }
        if !permissions.canPostEvents { return "Accessibility access required" }
        return midi.statusMessage
    }

    func selectProfile(_ profileID: UUID?) {
        selectedProfileID = profileID
        selectedPadIndex = nil
    }

    func selectPad(_ index: Int) {
        selectedPadIndex = index
    }

    func setUndoManager(_ undoManager: UndoManager?) {
        self.undoManager = undoManager
    }

    func selectedProfileBinding(at index: Int) -> PadBinding? {
        selectedProfile?.bindings.first { $0.index == index }
    }

    func displayedBinding(at index: Int) -> PadBinding? {
        if let local = selectedProfileBinding(at: index) { return local }
        guard selectedProfile?.isGlobal == false else { return nil }
        return configuration.profiles.first(where: \.isGlobal)?.bindings.first { $0.index == index }
    }

    func isInherited(at index: Int) -> Bool {
        selectedProfileBinding(at: index) == nil && displayedBinding(at: index) != nil
    }

    func assign(_ binding: PadBinding, to index: Int) {
        var copy = binding
        copy = PadBinding(index: index, label: copy.label, color: copy.color, action: copy.action)
        replaceSelectedBinding(copy)
    }

    func clearSelectedPad() {
        guard let selectedPadIndex else { return }
        replaceSelectedBinding(nil, at: selectedPadIndex)
    }

    func disableSelectedPad() {
        guard let selectedPadIndex else { return }
        replaceSelectedBinding(PadBinding(index: selectedPadIndex, label: "Disabled", color: .off, action: .disabled))
    }

    func updateSelectedBinding(label: String? = nil, color: PadColor? = nil, action: BindingAction? = nil) {
        guard let selectedPadIndex else { return }
        var binding = selectedProfileBinding(at: selectedPadIndex)
            ?? PadBinding(index: selectedPadIndex, label: "Untitled", color: .blue, action: .shortcut(.copy))
        if let label { binding.label = label }
        if let color { binding.color = color }
        if let action { binding.action = action }
        replaceSelectedBinding(binding)
    }

    func addApplicationProfile(bundleIdentifier: String, name: String) {
        guard !bundleIdentifier.isEmpty, !configuration.profiles.contains(where: { $0.applicationBundleIdentifier == bundleIdentifier }) else { return }
        let previous = configuration
        let profile = Profile(name: name, applicationBundleIdentifier: bundleIdentifier)
        configuration.profiles.append(profile)
        selectedProfileID = profile.id
        registerUndo(restoring: previous, actionName: "Add Preset")
        persistAndRefresh()
    }

    func chooseApplicationProfile() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application Preset"
        panel.message = "LaunchDeck switches to this preset while the application is active."
        panel.prompt = "Add Preset"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier else { return }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        addApplicationProfile(bundleIdentifier: bundleIdentifier, name: name)
    }

    func removeSelectedProfile() {
        guard let selectedProfile, !selectedProfile.isGlobal else { return }
        let previous = configuration
        configuration.profiles.removeAll { $0.id == selectedProfile.id }
        selectedProfileID = configuration.profiles.first(where: \.isGlobal)?.id
        selectedPadIndex = nil
        registerUndo(restoring: previous, actionName: "Delete Preset")
        persistAndRefresh()
    }

    func appCandidates() -> [ActiveApplication] {
        let selfBundleID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard let bundleIdentifier = application.bundleIdentifier,
                  bundleIdentifier != selfBundleID,
                  application.activationPolicy == .regular else { return nil }
            return ActiveApplication(application)
        }
        .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    private func replaceSelectedBinding(_ binding: PadBinding?, at index: Int? = nil) {
        guard let profileID = selectedProfileID else { return }
        let targetIndex = index ?? binding?.index
        guard let targetIndex, let profileIndex = configuration.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let previous = configuration
        configuration.profiles[profileIndex].bindings.removeAll { $0.index == targetIndex }
        if let binding { configuration.profiles[profileIndex].bindings.append(binding) }
        registerUndo(restoring: previous, actionName: binding == nil ? "Clear Pad" : "Edit Pad")
        persistAndRefresh()
    }

    private func registerUndo(restoring configuration: Configuration, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restore(configuration, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ restoredConfiguration: Configuration, actionName: String) {
        let previous = configuration
        configuration = restoredConfiguration
        if !configuration.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = configuration.profiles.first(where: \.isGlobal)?.id
            selectedPadIndex = nil
        }
        registerUndo(restoring: previous, actionName: actionName)
        persistAndRefresh()
    }

    private func persistAndRefresh() {
        let savedConfiguration = configuration
        Task.detached(priority: .utility) { [profileStore] in
            try? profileStore.save(savedConfiguration)
        }
        resolveRuntimeLayout()
    }

    private func updateActiveApplication(_ application: ActiveApplication?) {
        activeApplication = application
        actionExecutor.cancel()
        resolveRuntimeLayout()
    }

    private func resolveRuntimeLayout() {
        nextRevision += 1
        activeLayout = resolver.resolve(
            profiles: configuration.profiles,
            bundleIdentifier: activeApplication?.bundleIdentifier,
            revision: nextRevision
        )
        ledRenderer.render(activeLayout, paused: isPaused)
    }

    private func handle(_ event: PadEvent) {
        guard event.generation == midi.connectionGeneration else { return }
        switch event.phase {
        case .released:
            heldPads.remove(event.index)
        case .pressed:
            guard heldPads.insert(event.index).inserted else { return }
            guard !isPaused, !isLaunchDeckFrontmost else {
                selectPad(event.index)
                return
            }
            guard let binding = activeLayout.binding(at: event.index) else { return }
            let target = activeApplication?.processIdentifier
            actionExecutor.execute(
                binding.action,
                targetProcessID: target,
                canPostEvents: permissions.canPostEvents,
                targetIsStillFrontmost: { [weak self] processID in self?.activeApplication?.processIdentifier == processID },
                completion: { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .dispatched:
                        self.ledRenderer.flash(index: event.index, color: binding.color.highlighted)
                    case .rejectedBusy, .rejectedPermission, .cancelled:
                        self.ledRenderer.flash(index: event.index, color: .amber)
                    }
                }
            )
        }
    }

    private var isLaunchDeckFrontmost: Bool {
        activeApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
