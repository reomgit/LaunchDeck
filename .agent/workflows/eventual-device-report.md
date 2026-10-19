# Device/model implementation evidence

2026-10-06. Changes extend the dirty working tree without reverting, resetting, cleaning, or committing existing work.

Implemented:

- Mini MK3/X/Pro MK3/virtual descriptors and adapters, with Mini indices 0–79 unchanged. Pro adds 25 assignable perimeter controls for 105 total; the actual Novation programmer diagram and physical overview distinguish Shift CC90 from unassigned Setup and LED-only logo CC99. X uses product header 0x0C; Pro 0x0E; Mini 0x0D. All programmable controls have positions/names and press/release mappings.
- Independent per-model profile layouts; same-model Global inheritance; inherited ordering unless locally overridden; validation of all model bounds/folders/pages/orders/actions and local duplicate bindings before merging.
- Schema 1/2→3 migration validates before write, preserves IDs/layouts/activation/device ID, and creates an untouched versioned backup. Conflicting backups prevent replacement.
- Self-contained model-aware package schema 2, old package schema 1 import, all-model artwork embedding/remapping, and fresh consistent script consent UUIDs on every import. Imported script validation never executes code.
- Explicit MIDI selector and source unique IDs, same-device/same-entity pairing, MIDI-versus-DAW/DIN filtering, stop/suspend gates, connection-generation tagging at the CoreMIDI source-context boundary, and stale-event rejection.
- Dynamic LED encoding/repaint and invalidation of old flash restorations. Repaint sends off entries for every control rather than treating unknown hardware state as already black.
- Descriptor-driven native editor surface using the existing PadCell; Mini positions remain unchanged, X has 80 controls, Pro 105, and virtual 64. Geometry scales the full Pro surface to fit its extra rows.
- Structural MacroStep script/extension/HTTP cases, with script/HTTP validation delegated to their supplied types and missing extension references preserved.
- Root integration tests for editor isolation/persistence, copy preview, app inheritance, companion virtual resolution, stale press rejection with an injected executor, independent virtual folder navigation, activation synchronization, and absence of private action sources/URLs/bookmarks/secret references from snapshots.

Verification:

- `swift test --filter 'DeviceModelTests|EventualCoordinatorTests'`: 22 tests pass, no diagnostics, `/tmp/LaunchDeck-device-final.log`.
- Test-first evidence: schema2 migration failed returning2/missing backup before implementation; global-model order and local overlay duplicates failed before fixes; imported consent IDs failed equal to the original/repeated import before rekeying. Logs `/tmp/LaunchDeck-device-{order,script-import}-red.log`. New interface tests initially failed for unavailable APIs while parallel workers were still adding their contracts.
- Earlier whole `swift test`: 96 tests pass (21 XCTest + 75 Swift Testing), `/tmp/LaunchDeck-device-whole-tests.log`; it predates three final focused regressions and included a temporary unhandled-resource warning owned by the root package integration. Root must run the final whole suite.
- `git diff --check`: clean at final focused verification. SwiftPM compiled production core/services and the integrated coordinator. Native arm64/x86_64 builds and visual editor acceptance are root-owned final checks.

Docs: `docs/device-models.md` links primary Novation references and explains mappings, storage, migration, packages, and connection behavior.

Remaining verification limits:

- No connected Mini, X, or Pro hardware was available. Physical MIDI pairing/press/release, hotplug, suspend/wake, Live-mode restoration, LED clear/repaint, and real hardware device selection remain unverified. Protocol tests are not physical verification.
- Real phone/tablet browser testing and native editor screenshots remain root-owned. There is no intentional missing device/model user flow in this worker's implementation.

Root review findings were reported, and root confirmed fixing mismatched hardware/editor model selection, busy companion origin tracking, and MIDI selection synchronization after Undo.
