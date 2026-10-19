# Full eventual workflow implementation plan

Approved 2026-10-06: user delegates all remaining decisions. Use recommended design in `docs/superpowers/specs/2026-10-06-eventual-workflows-design.md`. Preserve all dirty working-tree edits and existing 52 tests. Work in current `codex/desktop-workflows` checkout.

## Ordered milestones and verification

1. Device/model schema: descriptors/adapters Mini/X/Pro/virtual, stable existing indices, model-specific independent profile layouts, Global inheritance, schema1/2→3 backups, model-aware packages, MIDI endpoint pairing/selection/generations, dynamic LEDs. Add migration/mapping/inheritance/portability tests before implementation; check actual Pro protocol diagram. Root integrates model selection, layout-copy preview and physical editor descriptors.
2. Actions: root adds native shell/AppleScript process executor, permission store/onboarding and UI/macro editing. Extension worker adds portable manifests/action params, registry/install/update/remove/enable, HTTP service actions/secret references, example integration and editor panels. Root integrates extension expansion with existing single runner so permission/focus checks apply to expanded steps. Validate packages without executing them. Test errors/cancellation/timeout/process tree, missing extensions, atomic updates, secrets excluded.
3. Community: catalog fetch/search/filter/digest download and install profile/icon/extension packages, bundled working starter content, user-configurable HTTPS catalog, loopback HTTP test. Expose installed artwork and update discovery. Never fabricate a hosted marketplace.
4. Companion: paired responsive phone/tablet browser deck served by Network.framework, revisioned snapshots/artwork/runtime state, stale press checks, activation/navigation through shared coordinator/executor, revocation/stop/reconnect. Root integrates independent virtual layouts and settings window. Real loopback integration tests, responsive browser QA; physical devices when available.
5. Distribution: optional credential-driven Developer ID hardened runtime/notarize/staple pipeline, maintain preview path, document secrets without printing them, validate scripts/config locally. Actual signed artifact remains unverified without supplied credentials.
6. Whole change review, `swift test`, arm64/x86_64 native builds, plist/diff checks, UI and loopback acceptance, README/continuity/requirements audit. Keep goal incomplete while required user flows or verification remain missing.

## Ownership

- Device worker: Core/Models.swift, ProfileStore, ProfileResolver, ProfilePackageStore, ConfigurationOperations; new DeviceAdapters; Services/MIDIService and LEDRenderer; device tests/docs.
- Ecosystem worker: new ExtensionModels/ExtensionRegistry/ContentCatalog/IconPackStore; new HTTPActionExecutor/SecretStore/ContentLibraryService; new EcosystemViews; ecosystem tests, sample artifacts and authoring docs. No existing Models/Coordinator/editor edits.
- Companion worker: new CompanionModels/CompanionServer/CompanionHTML/CompanionSettingsView; companion tests/docs. No existing Coordinator/editor edits.
- Root: ScriptAction/ScriptExecutor/ScriptApprovalStore, ActionRunner/ActionExecutor, AppCoordinator, EditorView/PadInspector/ProfileWorkflowViews, LaunchDeckApp, Info.plist/Package.swift, signing workflow, README/continuity/integration tests.

Everyone is sharing the codebase. Preserve others' edits; do not revert/commit/reset/clean shared work. Send interfaces before integration. Tests can temporarily fail compilation while another owned subsystem is in flight; record and distinguish that from own defects. No system installs, external writes, real unapproved service commands, or privileges changes.

## Shared action contract

Device worker adds MacroStep.script(ScriptAction), extensionAction(ExtensionInvocation), httpRequest(HTTPRequestAction), with displayName and structural validation. Types supplied by root/ecosystem worker; no scripting/extension implementation in Models. ActionRunner performs script/http via injected `perform`; ActionExecutor expands extension invocations before running so focus/permission detection includes all recipe keyboard steps.

Root's ScriptAction: Codable/Hashable/Sendable with id UUID, language ScriptLanguage (.shell/.appleScript), source ScriptSource (.inline(String)/.file(FileTarget)), arguments [String], timeoutSeconds Int, targetBundleIdentifiers [String]. Default init(source:language:arguments:timeoutSeconds:targetBundleIdentifiers:) supplies UUID; enabled state is local permission store, never exported.

Ecosystem worker supplies ExtensionInvocation(extensionID:String,actionID:String,parameters:[String:String]=[:]); HTTPRequestAction Codable/Hashable/Sendable request with url/method/headers/body/allowedHosts/secretHeaders/timeoutSeconds. APIs: ExtensionRegistry(directory:), installedExtensions, install(from:) throws, remove(id:) throws, setEnabled(id:enabled:) throws, expandSteps(_:[MacroStep]) throws->[MacroStep]; HTTPActionExecutor.execute(_:secrets:) async throws; SecretStore secret/save/remove API with Keychain storage. ContentLibraryService owns observable catalog/installed status and async fetch/download; callback for profile import lets root append/undo safely.

Device worker retains existing Profile.pages/folders/order as Mini layout compatibility; adds DeviceModel and Profile.layout(for:)/setLayout(_:for:), DeckModelLayout pages/folders/orders. Resolver methods accept optional/default model .miniMK3. ResolvedLayout exposes controlCount/model. MIDIService exposes devices, selectedDeviceUniqueID, connectedModel, selectDevice(_:) and retains existing callbacks/generation. DeviceDescriptor supplies indexed control positions/names plus controlCount and MIDI messages. Virtual has 64 square controls.

Companion contracts are callback driven, avoid coordinator coupling: CompanionSnapshot DTO contains revision/profile/mode/page/model/controls/profiles/feedback; each control contains index/label/action/color/symbolName/artworkID/row/column. CompanionServer onSnapshot, onPress(index:revision:pageID:), onActivate(profileID?), onArtwork(id:)->Data?, onStop. start/stop, pairingCode, URLs/status/clients, revokeClient. Server validates credential/origin/body/rate; root validates revision/page and routes runtime execution. HTML embedded in Swift string keeps app single-target/no dependencies.

## Final software checkpoint

All owned implementations are integrated and reviewed;112tests pass. Native arm64/x86_64 builds and desktop/browser UI verification completed. See `eventual-requirements.md` for logs and precise remaining physical/credential-dependent acceptance. README/SDK/sample/catalog/device/companion/distribution docs updated. No actual release or service command was issued. User working-tree improvements preserved; no blanket commit/reset.
