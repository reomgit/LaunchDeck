# Core workflow delivery

Implemented Models/ProfileResolver/ProfileStore and new DeckNavigation, ConfigurationOperations, ProfilePackageStore; new WorkflowTests only. Compatibility accessors preserve bindings/home and PadBinding construction.

Schema 1 is decoded using actual legacy Codable keys, validated, copied exactly to profiles.v1.backup.json, then replaced atomically with schema 2. Unknown/corrupt input remains intact and throws. Existing conflicting backup prevents migration.

Application effective pages merge controls by stable page/index IDs; folders overlay by stable ID. Manual profiles are independent. Explicit activation accepts any existing profile. Navigation records folder entry history; page turns stay within folder boundaries, Home clears history.

Packages use a single JSON .launchdeckprofile file containing manifest plus base64 image assets. Exports materialize inherited application layouts; imports produce a fresh independent Manual ID and fresh artwork IDs. All manifest references/actions/images are validated before asset writing; write errors clean up newly written assets. Images are decoded and normalized to PNG; one frame, 4096-pixel dimension limit and 20MB source limit. ConfigurationOperations.materialize supplies duplication helper. importArtwork(data:fileExtension:) added for composer (format hint ignored; native image decoder determines real format).

Validation checks global uniqueness, IDs, app identifiers, profile kind consistency, home root position, controls/colors, macros/resources/web protocols, bookmark data/path shape, folder/page/navigation references, cycles, and artwork UUIDs. FileTarget resolves and rejects stale bookmarks during action execution; configuration validation intentionally does not resolve resources, so unavailable files do not prevent configuration loading.

Tests: initial tests failed with missing APIs before implementation. Ten isolated Core XCTest workflow tests passed (swift test --package-path /tmp/launchdeck-core-tests.pqaJTP), including migration backup, unknown/corrupt preservation, overlays/activation/manual independence, folder history, package materialization and actual image asset round trip. Full shared swift test was temporarily blocked by concurrent AppCoordinator switch missing .failed result; root owns integration. Native Data does not support atomic + withoutOverwriting together; observed runtime failure and corrected exclusive backup/asset writes before passing tests.

Concerns: packages keep native file bookmarks; they can become stale or unavailable across machines, with action execution surfacing repair guidance. No shell or executable payload accepted. Artwork UUID validity is checked by ProfileStore, while package importer checks actual image references; ordinary configuration save cannot enforce file presence without coupling storage paths. All files are uncommitted for root integration.

## Review corrections

Optional pageOrder/folderOrder fields honor explicit inherited-view order without moving a renamed overlay implicitly. MacroStep and NavigationAction expose specific display names. Native image importer accepts PNG/JPEG only. Removed new macro-size and delay-ceiling restrictions to retain real v1 compatibility. Tests cover inherited ordering, metadata stability, 257-step/60001ms macros, missing-file bookmark validity, unreferenced package assets, folder cycles, and GIF rejection; all 10 isolated workflow tests pass.
