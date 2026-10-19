# Companion implementation report

2026-10-06 [CODE] Owned additions: `Core/CompanionModels.swift`, `Services/CompanionServer.swift`, `Services/CompanionHTML.swift`, `Views/CompanionSettingsView.swift`, `Tests/LaunchDeckCoreTests/CompanionTests.swift`, `docs/companion/README.md`. No existing coordinator/models/package/plist files edited.

## Integration APIs

MainActor observable `CompanionServer()`; `start(port: UInt16 = 0, loopbackOnly: Bool = false) throws`, `stop()`, `renewPairingCode()`, `revokeClient(id: UUID)`. Observed `isRunning`, `urls`, `pairingCode`, `pairingExpiresAt`, `clients`, `status`. The ready callback populates URLs asynchronously. `CompanionSettingsView(server:)` supplies native Start/Stop, addresses/copy/QR selection, expiring code and paired-browser revocation.

Callbacks: `onSnapshot: (() -> CompanionSnapshot)?`, `onPress: ((Int, Int, UUID) -> String?)?`, `onActivate: ((UUID?) -> String?)?`, `onArtwork: ((String) -> Data?)?`, `onStop: (() -> Void)?`. Error strings return conflict; nil accepts. Root coordinator validates revision/page/control and routes one executor/navigation; root owns cancellation on stop/quit. Runtime snapshot initializer: `revision`, `profileID = nil`, `profileName`, `mode`, `pageID`, `pageName`, `model = "virtual"`, `rows = 8`, `columns = 8`, `controls = []`, `profiles = []`, `feedback = nil`. Controls initializer: `index,row,column,label,action,color,symbolName = nil,artworkID = nil,feedback = nil,enabled = true`. Profile initializer `id,name`. DTOs deliberately carry no action recipes/bookmarks/secrets.

## Evidence

- Test-first suite added before production files; initial full-package run was blocked by concurrent missing ecosystem symbols. Companion-only temporary package isolated source/testing from other workers; six tests passed in `/tmp/LaunchDeck-companion-isolated.log`.
- A selected-port regression first reproduced Network.framework `EINVAL` when an explicit local endpoint and listener port were both configured. Server now sets the selected port once for loopback listeners; failing case turned green (`/tmp/LaunchDeck-companion-port-red.log`).
- Native Swift 6 typecheck of DTO/server/HTML/settings succeeded without diagnostics (`/tmp/LaunchDeck-companion-typecheck.log`).
- Browser QA on actual Network.framework server with a safe synthetic 64-control snapshot: paired successfully; press produced live `Control 1 accepted.` feedback; Auto activation changed displayed profile to Global; browser console had no errors. Phone 390×844: 64 controls, deck366px, no horizontal overflow. Tablet 1024×768 landscape originally clipped bottom rows (deck bottom1081); breakpoint adjusted and verified all64 controls/deck bottom659/footer763. Killing server yielded `Reconnecting…` and all64 buttons disabled. Restart required new pairing. CUA viewport reset and created fixture tab closed afterward.
- HTTP/auth protections: five-minute secure-random code; separate 256-bit bearer per browser; revocation and stop invalidation; local Host and same-origin checks, cross-site rejection, bounded connections/headers/bodies/response artwork/rates. Fragmented TCP parser test uses real sockets; rejects duplicate lengths/chunked encoding/oversized content.

## Remaining integration/limits

Root supplied callback binding, virtual-layout editor controls and source-specific cancellation during this task; root owns full integration verification. Read-only coordinator review flagged URL/query/userinfo exposure via action.displayName and raw script stderr/file paths via feedbackMessage; root implemented generic action-type descriptions and separate safe companion feedback; repeated read-only review confirms raw URL/command/error content is excluded. Whole-app native builds/full-suite verification are root-owned. No physical phone/tablet or Wi-Fi/firewall verification performed. Browser tests use a fixture rather than real desktop action execution. HTTP is intended for trusted IPv4 local networks; no IPv6-only advertisement, TLS, cloud relay or mobile layout editing. SF Symbols have browser Unicode equivalents/fallback while normalized PNG artwork preserves imported visuals. Stop revokes sessions; Mac does not persist credentials, browser storage belongs to its own origin.

2026-10-06 [TOOL] Integrated `swift test --filter CompanionTests` passes all six tests (`/tmp/LaunchDeck-companion-integrated.log`). Revocation callback regression first failed (cancellationCount0 instead of1) and passed after existing-client revoke invokes onStop (`/tmp/LaunchDeck-companion-revoke-red.log`). Unknown-client revoke does not invoke cancellation. Native typecheck repeated after change, clean. Fixture process stopped; preview viewport reset and tab closed.

2026-10-06 [CODE] Root requested read-only script executor/approval review. Sent concrete findings: TERM-ignoring detached children can survive escalation gated by finished; mutable file fingerprint/read TOCTOU can execute newly changed bytes after consent; profile re-import preserves script IDs and may inherit earlier approval contrary to fresh-import enabling requirement. Root owns fixes/tests.

2026-10-06 [TOOL] x86_64 Swift6 native typecheck also succeeded without diagnostics (`/tmp/LaunchDeck-companion-x86-typecheck.log`); this supplements arm64 checks without claiming whole-app build verification.
