// SPDX-License-Identifier: GPL-3.0-only
// Copyright © 2026 Reom Nagasaka

import AppKit
import Observation

struct ActiveApplication: Equatable, Sendable {
    let bundleIdentifier: String?
    let localizedName: String
    let processIdentifier: pid_t

    init(_ application: NSRunningApplication) {
        bundleIdentifier = application.bundleIdentifier
        localizedName = application.localizedName ?? "Unknown App"
        processIdentifier = application.processIdentifier
    }
}

@MainActor
@Observable
final class ActiveAppMonitor {
    private(set) var activeApplication: ActiveApplication?
    var onChange: (@MainActor (ActiveApplication?) -> Void)?

    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.setActiveApplication(ActiveApplication(application))
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func refresh() {
        setActiveApplication(NSWorkspace.shared.frontmostApplication.map(ActiveApplication.init))
    }

    private func setActiveApplication(_ application: ActiveApplication?) {
        guard activeApplication != application else { return }
        activeApplication = application
        onChange?(application)
    }
}
