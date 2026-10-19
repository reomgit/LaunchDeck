# Ecosystem worker report

2026-10-05T23:07Z [CODE] Implemented the approved extension and community content scope in new owned files. Shared/preexisting edits were preserved; no commits, resets, installs, external service writes, or permission changes were performed.

## Delivered

- `Core/ExtensionModels.swift`: versioned manifest/actions, typed parameters, portable invocation references, structurally validated HTTP actions, recoverable error messages.
- `Core/ExtensionRegistry.swift`: observable installed actions, complete semantic recipe/parameter validation, atomic lifecycle persistence, compatible updates preserving prior enabled state, recoverable unavailable references, bounded recipe expansion, no nested extension calls, structured script argument substitution and JSON-safe HTTP body substitutions. Secret references cannot become text/script/URL content.
- `Services/HTTPActionExecutor.swift` and `SecretStore.swift`: HTTPS/exact declared hosts (HTTP only on loopback), same-origin redirect enforcement, bounded streamed responses, cancellation/resource timeout, non-2xx errors, ephemeral cookie/credential-free sessions, locally configured Keychain header references. Sensitive headers cannot be literal exported credentials. Secret reads disable interactive authentication, using current LAContext API.
- `Core/ContentCatalog.swift`, `Services/ContentLibraryService.swift`: versioned user HTTPS catalog; query/type/model/application/service metadata discovery; bounded download with exact size/SHA-256 validation; ID/version matching; update discovery; independent callback-driven profile import; all three offline starter package types; remembered catalog URL. No fabricated marketplace URL.
- `Core/IconPackStore.swift`: author/license metadata; PNG/JPEG normalization via existing package store; fresh local IDs; malformed install/update rollback; previous assigned artwork retained when updating/removing pack metadata.
- `Views/EcosystemViews.swift`: native Content Library/Extensions panels, file and catalog installs/updates/removal, enable controls, local secret input, invocation parameter editor, and installed artwork chooser. Root integrated panels into Tools/menu bar and normal pad/macro flows. Artwork picker adapts to the narrow inspector. Boolean/choice editors show an explicit unselected state rather than falsely presenting missing required values as chosen.
- `Samples/Ecosystem/`: installable Home Assistant integration, Desktop Starter profile, actual Home/Play/Folder PNG icon pack, checksum-bearing loopback catalog, serving instructions. HTTP example is based on the Home Assistant REST API primary documentation inspected 2026-10-06; installation performs no request to a real service.
- `docs/ecosystem/`: full extension SDK, catalog/icon authoring, three JSON schemas, local sample serving/regeneration workflow.

## Verification

2026-10-05T23:06Z [TOOL] `swift test --filter Ecosystem` passed **15 tests** with zero ecosystem warnings/errors. Log: `/tmp/LaunchDeck-ecosystem-final-tests.log`.

Coverage includes installed lifecycle/serialization/reload, malformed update preservation, required/unknown parameters, disabled/missing actions, corrupt-registry preservation, catalog query/model validation, checksum/size validation, icon fresh IDs/normalization/rollback, offline starter installation, checked-in package verification/import, source-unchanged structured script arguments, secret-reference containment/literal credential rejection, and IPv6 loopback validation.

Real loopback tests cover HTTP secret header injection, status errors, cross-origin redirect rejection, timeout/cancellation, catalog installation and compatible update discovery, corrupt digest rollback, all three package types downloaded over HTTP, and repeated independent profile imports preserving an existing profile.

The first focused red phase identified missing new APIs; subsequent true behavioral red phases caught invalid prototype PNG CRC, missing sample artifacts, exported literal Authorization header acceptance, and unknown catalog model acceptance. Fixed these at their source and reran green. Shared root API changes temporarily produced a stale script-approval linker error; the subsequent complete focused run passed.

`git diff --check` passed. Checked all sample artifact byte counts/SHA-256 values independently with Python standard libraries; all three authoring schemas parse as JSON. Parent reports integrated arm64 native build passed in `/tmp/LaunchDeck-eventual-build.log`, including ecosystem panels; final picker-only layout refinements need the final root native rebuild/QA.

## Root integration review

Reported actionable findings to root: profile imports must regenerate script UUIDs so existing approvals cannot transfer; approvals should support multiple exact parameter sets of the same extension script UUID; extension script previews must be read-only instead of displaying ignored edits; notarized artifacts need corresponding source/license. Root owns fixes and final acceptance for these cross-subsystem areas. Follow-up source review confirms multiple UUID+fingerprint approvals, disabled read-only recipe edit controls with an active approval toggle, source/license artifacts, and profile-import script ID regeneration across all model layouts/macros are now present.

Extension registry corrupt-state handling correctly preserves the original and prevents unavailable library operations. Script/extension menus, macro editing, HTTP performer, profile undo callback, unavailable-action feedback, and installed artwork are connected in the reviewed native code.

## Practical limits

No real Home Assistant server, credentials, Launchpad hardware, physical phone/tablet, or Developer ID credentials were used by this worker. Automated transport tests use isolated loopback fixtures and a synthetic secret provider; Keychain runtime access itself is not exercised. Native visual interaction and whole-app/architectures/distribution acceptance remain root's final verification responsibility. The custom catalog is user-configured; there is no hosted account marketplace.

2026-10-05T23:08Z [TOOL] Final coordinated worker run after the root script API settled again passed all 15 ecosystem tests; no ecosystem warning/error matches. Shared tests are released for root whole-suite verification.
