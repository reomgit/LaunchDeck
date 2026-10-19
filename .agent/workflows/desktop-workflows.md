# Desktop workflows implementation ledger

Approved 2026-09-30 by user. Extend current dirty checkout; preserve existing 80-control and editor changes. macOS 26+, Swift-only, GPL-3.0-only. No additional hardware, plugin marketplace, or mobile companion in this delivery.

## Tasks
- [x] Core models, v1 migration/backup, profile resolution, navigation, portable packages and tests.
- [x] Injected action execution, native resource opening, Unicode events, feedback and tests.
- [x] Editor profile/view management, action/macro inspector, artwork composer and preview.
- [x] Coordinator integration, serialized persistence, activation/menu bar, documentation.
- [x] Whole-change review, 48 tests, arm64/x86_64 builds, isolated native UI smoke check. Physical-device and actual target-app keyboard dispatch remain unverified: no Launchpad connected, isolated QA app has no Accessibility permission.

## Shared interfaces
Models retain Shortcut, PadColor, PadBinding(index:label:color:action:), Profile(id:name:applicationBundleIdentifier:bindings:) compatibility.
MacroStep adds launchApplication(bundleIdentifier: String), openFile(FileTarget), openFolder(FileTarget), openWebsite(String), text(String), retains shortcut(Shortcut), delay(milliseconds: Int). FileTarget stores bookmark Data and display path; init(url:) throws, resolvedURL() throws.
BindingAction retains shortcut, macro, disabled; adds step(MacroStep), navigation(NavigationAction). NavigationAction is openFolder(UUID), back, home, previousPage, nextPage.
PadBinding adds symbolName: String? and artworkID: String?.
ProfileKind is global/application/manual. Profile has kind, pages: [DeckPage], folders: [DeckFolder]; .bindings is home page bindings compatibility accessor. DeckPage(id:name:folderID:bindings:) defaults home root ID through static DeckPage.homeID. DeckFolder(id:name:parentFolderID:). Both Identifiable Codable Hashable Sendable.
Configuration version 2 adds manuallyActivatedProfileID: UUID?.
ProfileResolver: activeProfile(profiles:bundleIdentifier:manuallyActivatedProfileID:) -> Profile?; effectivePages(profile:global:) -> [DeckPage]; effectiveFolders(profile:global:) -> [DeckFolder]; resolve(profiles:bundleIdentifier:revision:profileID:pageID:) -> ResolvedLayout, last two parameters optional defaults.
DeckNavigation stores pageID and history. reset(pages:), perform(_:pages:folders:) returns Bool, reconcile(pages:).
ProfileStore: load/save continue; validate public internal; load migrates v1 and writes backup then version 2, file-not-found allowed to coordinator default only.
ProfilePackageStore(directory:) export(profile:global:to:) throws, importProfile(from:) throws -> Profile (new independent Manual ID), artworkURL(for:) -> URL, importArtwork(from:) throws -> String. Self-contained .launchdeckprofile file package manifest and assets; strict references and image checks. Duplicating app profile materializes effective layout as manual.
Action execution API to be announced by executor worker before coordinator integration. Editor coordinator API to be announced by root before editor dispatch.

## Editor/coordinator contract
Root owns AppCoordinator.swift, LaunchDeckApp.swift, Package.swift, README/continuity. Editor worker owns EditorView.swift, new Views/ UI files, Services/ArtworkComposer.swift, Info.plist.
Coordinator properties: selectedProfile, selectedProfileID, selectedPadIndex (existing); selectedPageID: UUID; editorPages: [DeckPage]; editorFolders: [DeckFolder]; selectedPage: DeckPage?; runtimeProfile: Profile?; runtimeDescription: String (mode/profile/page); feedbackMessage: String?; persistenceError: String?; canDeleteSelectedPage: Bool; canDeleteFolder(_ id: UUID) -> Bool.
Methods: existing selection/assign/clear/disable/update; updateSelectedBinding(label: String? = nil,color: PadColor? = nil,action: BindingAction? = nil). setSelectedSymbol(_ name: String?), setSelectedArtwork(_ id: String?), chooseArtwork(), composeSelectedArtwork() calls ArtworkComposer.render(label:symbolName:color:) -> Data? and stores PNG. artworkURL(for: String) -> URL.
Profiles: addManualProfile(name: String = "New Profile"), renameSelectedProfile(_ name: String), duplicateSelectedProfile(), removeSelectedProfile(), chooseApplicationProfile(), activateProfile(_ id: UUID), activateSelectedProfile(), useAutoProfiles().
Views: selectPage(_ id: UUID), createPage(name: String = "New Page",folderID: UUID? = nil), createFolder(name: String = "New Folder",parentFolderID: UUID? = nil) creates first page too, renamePage(_ id: UUID,name: String), renameFolder(_ id: UUID,name: String), movePage(_ id: UUID,by: Int), moveFolder(_ id: UUID,by: Int), deletePage(_ id: UUID), deleteFolder(_ id: UUID). Protect home page and inherited views from deletion in app profile.
Packages: importProfile(), exportSelectedProfile() native panels. clearFeedback(). executeNavigation(_ action: NavigationAction) applies runtime navigation. Editor page selection changes preview only.
ActionExecutionResult core cases dispatched/rejectedBusy/rejectedPermission/cancelled/failed(String). ActionExecutor existing execute signature plus activeApplicationChanged(processID:). Root will remove unconditional app-change cancellation.

## Progress
- 2026-09-30 [TOOL] Existing 10 core tests passed during planning. Branch codex/desktop-workflows created without altering prior edits.
- 2026-09-30T09:16Z [TOOL] Final swift test passes 48 tests (10 XCTest +38 Swift Testing). Both final architecture builds succeed; no Swift source warnings. Xcode emits its expected skipped AppIntents metadata advisory because this utility has no AppIntents dependency. Plist lint and git diff --check pass.
- 2026-09-30T09:16Z [TOOL] Independent review has no open important issues after two regression-tested inheritance corrections. UI smoke check used an isolated /tmp app/data store: all 80 controls fit, editor inspector/label/symbol/composed artwork, profile creation and folder/page creation verified. User's live profiles were not used for UI testing.
- 2026-09-30T09:16Z [CODE] Shared contract follow-ups: Profile.pageOrder/folderOrder optional arrays; execute(_:targetProcessID:canPostEvents:completion:) excludes old predicate argument. Profile packages are single public.data JSON files with embedded normalized PNG artwork, not directory packages.
