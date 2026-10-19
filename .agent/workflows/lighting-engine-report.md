# Lighting engine implementation report — 2026-10-16

Owned files: `LaunchDeck/Core/Lighting.swift`, `LaunchDeck/Services/LEDRenderer.swift`, `Tests/LaunchDeckCoreTests/LightingTests.swift`.

Implemented spec settings (Codable/Hashable/Sendable), partial-object decode defaults and strict `validate()` for finite numeric ranges, exactly64 art pixels and 7-bit RGB. Pure `LightingComposer.frame(layout:time:presses:statuses:applicationStates:audioLevel:)` layers static colors/art, ambient motion, actual-launch-app indicators, bounded transients and action status; disabled masks/brightness apply last. Existing two-argument composer calls work via defaults. Grid indices retain bottom-left0 / top-left56; outer controls retain binding colors unless individually pressed/status-marked.

Renderer retains init/render/repaint/flash APIs and implements all plan APIs plus injected monotonic clock and automatic scheduling toggle. Transients cap at24. Animation tasks weakly capture the renderer, run at most30Hz, and disappear when static. Static audio/application/status changes coalesce through one pending frame. Model changes, revision/render, repaint, pause and stop invalidate tasks/transients. `stop(clear:false)` sends nothing; frame callbacks can still reflect black. Device frame output sends only changed entries. Application states only modify direct launch-app bindings; action status takes precedence over legacy flashes.

TDD evidence:

- Existing API regression `disabledControlRejectsLegacyFlash` failed with a green SysEx on disabled index0; guard fixed it and focused test passed.
- Missing settings/composer APIs produced expected compile failures before definitions were added.
- Concrete `coalescedAudioUpdateEventuallyPublishesWithoutPermanentMotion` red showed static/audioMeter update lost after throttling; pending-frame scheduling fixed it.
- Concrete `actionStatusRemainsAboveLegacyFlashAndCanBeCleared` red showed flash wrongly taking precedence; active status now wins and restores correctly.
-18 lighting tests cover deterministic ripple/cross/sparkle geometry, ambient changes, literal bottom-up audio levels, brightness/7-bit constraints, disabled masks, app-state truthfulness, exact restoration, diff batches, bounded event eviction,30Hz coalescing, weak task ownership, automatic stop cancellation and per-device independence.

Verification: `swift test --scratch-path /tmp/LaunchDeck-lighting-build` passed155 tests in22 suites after final changes (`/tmp/LaunchDeck-lighting-final-suite.log`). Scoped `git diff --check` passed. Earlier full run exposed a fixed80ms scheduling assumption in an asynchronous test; replaced with bounded polling of the actual frame. Temporary focused copy package was used while parent integration temporarily did not compile; final verification used the actual shared package.

No hardware, CUA, action execution or real audio capture was performed by this worker. Actual USB brightness/timing remains unverified. Parent owns integration and final architecture/UI checks. No commits, resets or stashes.
