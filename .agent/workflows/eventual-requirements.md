# Eventual goals — implementation and acceptance audit

2026-10-05T23:13Z / 2026-10-06 local. User’s “Sure, just you decide everything” supersedes the earlier design approval blocker. Design: `docs/superpowers/specs/2026-10-06-eventual-workflows-design.md`. Execution ledger: `.agent/workflows/eventual-implementation.md`. No further design permission is pending.

| Requirement | Implemented and verified evidence | External acceptance remaining |
|---|---|---|
| Assign/show/clear/disable Mini controls | All80 mapping tests, model-aware disconnected editor, inheritance/disabled previews | Physical input/LED acceptance |
| Launch apps/files/folders/websites, Unicode text, shortcuts, mixed sequences | Native executor plus injected runner ordering/handoff/permission/cancellation/failure tests | Permission-controlled actual target acceptance and launch→delay→shortcut workflow |
| Sleep/session/disconnect/pause/shutdown cancellation | WorkspaceSessionMonitor, MIDI lifecycle gating and regression coverage | Physical sleep/session/reconnect |
| Global/Application/Manual profiles, editor/runtime activation, inheritance | Coordinator persistence/deletion fallback/undo tests, all model overrides, independent preview | Hardware navigation feedback |
| Stable ordered pages/nested folders and assignable navigation | DeckNavigation, inherited/deleted reference tests; virtual history independently routed | Physical button navigation |
| Appearance/artwork/effective portable profiles | Picker/composer, profile package validation/round trips/allmodels, normalized images, rekeyed imported script IDs | Visual hardware LEDs (hardware does not show artwork) |
| Mini/X/Pro device adapters and virtual layout | Mini/X80, Pro105, virtual64 descriptors; protocol/LED/mapping tests, same-device MIDI pairing, persisted selection/generations; native Pro preview all105 visible | Real X/Pro compatibility/input/RGB feedback |
| Schema1/2 migration to3 and protected originals | Migration backups/preserved IDs/associations/order/indices and failures tested; model layouts exported together | None required for software behavior |
| Shell/AppleScript and local enabling | Literal arguments, file bookmarks, bounded capture, immutable approval-matched bytes, local multiple exact fingerprints, Automation guidance, output/timeout/cancel/nonzero failures;14 native script tests | Actual Automation access to chosen apps; signed runtime behavior |
| Extension discover/install/update/enable/remove and actions | Observable atomic registry, parameterized recipes, keyboard checks after expansion, allowed-host HTTP transport, Keychain references, inspector/macro menus, SDK/schemas | Real service configuration remains user-specific |
| Community content and icon packs | Search/filter catalog panel, HTTPS configurable source, digest/size validation, installed updates; real loopback all3 package types and rollback; actual offline packages | No hosted marketplace operated by this repo |
| Phone/tablet companion synchronized with desktop | Network.framework server, QR/pairing/auth/revoke, safe presentation DTOs, stale presses, shared executor, virtual history; real TCP tests and actual-server browser phone/tablet QA | Physical phone/tablet over Wi-Fi/firewall |
| Optional Developer ID distribution | Hardened runtime Apple Events entitlement; credential-driven sign/notary/staple/Gatekeeper workflow, source/license artifact, Bash/YAML/plist/localCLI checks | Actual accepted ticket requires configured Developer ID credentials |

Final software verification: `swift test` passes **112 tests** (25 XCTest +87 Swift Testing) in `/tmp/LaunchDeck-acceptance-tests.log`; existing10 core tests retained. Native arm64 final editor build `/tmp/LaunchDeck-editor-inset.log`; x86_64 final build `/tmp/LaunchDeck-acceptance-intel.log`. Both use signing disabled; these are not signed release acceptance. `git diff --check`, Bash syntax, Info/entitlement plists and workflow YAML parsed cleanly.

Independent reviews corrected companion URL/rawerror exposure, local file consent race, detached TERM-ignoring descendant cleanup, imported consent reuse, parameterized approval collisions, editable-but-no-op recipe fields, and source/license distribution artifacts. Browser snapshots now expose generic action descriptions and safe status; detailed execution errors stay on the Mac.

Native CUA checks: disconnected editor model picker and Pro105 surface; runtime header visible; copy dialog shows64 positional mappings to virtual and replacement/Undo description; community panel lists3 actual offline entries. Surface collapse/top-toolbar underlap found in screenshot and repaired, then verified after rebuild/relaunch. No user Accessibility/Automation settings changed; no real service commands issued. Preview uses existing config; schema migration backup protects its original. Working tree remains uncommitted because it includes existing user improvements.

The earlier goal was blocked awaiting design approval; that condition has been resolved and full software scope implemented. Full hardware/credential-dependent acceptance remains unproven; do not claim an actual notarized release or physical device verification.
