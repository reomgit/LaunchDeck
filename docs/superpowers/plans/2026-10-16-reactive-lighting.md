# Reactive Lighting Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development and dispatching-parallel-agents for the independent composer/renderer, artwork importer and audio-input tasks. Preserve others' changes.

**Goal:** Configurable reactive/ambient/status lighting and portable LED grid artwork across all connected Launchpads, with optional user-enabled audio input.

**Architecture:** Pure deterministic frame composition feeds the existing per-device LEDRenderer; optional page/binding settings resolve through current inheritance. A dedicated no-output renderer previews effects. Audio produces loudness only and cannot activate from imported configuration.

**Tech Stack:** Swift 6.2+, macOS 26+, SwiftUI/AppKit, CoreMIDI, CoreGraphics/ImageIO and AVFoundation.

**Spec:** `docs/superpowers/specs/2026-10-16-reactive-lighting-design.md`

## Global Constraints

- Preserve the current dirty checkout, native Liquid Glass, shared mappings and per-device routing.
- Disabled pads and paused/stopped output stay black, including artwork/effect overlays.
- No dependency installs, permission grants, microphone recording or external service actions during QA.
- Profile imports cannot enable microphone capture.

## Review Focus

- Old restoration callbacks and tasks cannot repaint a reconnected device or new page.
- Inherited/dormant settings and copied bindings retain every lighting property.
- Top/bottom image orientation and disabled pixels are independently verified with literal fixtures.
- Live audio permission revocation/suspension cannot leave capture or stale loudness active.
- Editor preview does not send hardware actions and idle rendering does not spin a permanent task.

### Task 1: Deterministic lighting and renderer (worker)

Own `Core/Lighting.swift`, `Services/LEDRenderer.swift`, `Tests/LaunchDeckCoreTests/LightingTests.swift`. Define exact settings/enums from spec, composer and `LightingActionStatus` (.running/.success/.failure), `ApplicationLightState` (.running/.frontmost). Keep renderer existing init/render/repaint/flash APIs; add init optional `clock: () -> TimeInterval`, `automaticallyAnimate: Bool`; `onFrame: (([Int:PadColor])->Void)?`, `press(index:effect:color:)`, `setStatus(index:status:)` (optional status), `setApplicationStates(_:)`, `setAudioLevel(_:)`, `stop(clear:)`, `tick()`. Renderer obtains `ResolvedLayout.lighting` and optional binding.pressEffect, supplied by parent. Observe focused failing tests before implementation and prove full restoration/cancellation.

### Task 2: Safe image-to-grid importer (worker)

Own `Services/LEDGridArtwork.swift`, `Tests/LaunchDeckCoreTests/LEDGridArtworkTests.swift`. API `LEDGridArtwork.colors(from data: Data) throws -> [PadColor]`, PNG/JPEG single image, ≤20 MB, dimensions≤4096, EXIF orientation, exactly64 7-bit RGB values, top-left index56. Use pure ImageIO/CoreGraphics and literal quadrant/alpha/orientation fixtures. Parent owns UI/file picker. No image generation or alteration of user files.

### Task 3: Optional loudness input (worker)

Own `Core/AudioLevel.swift`, `Services/AudioReactiveMonitor.swift`, `Tests/LaunchDeckCoreTests/AudioReactiveTests.swift`. API MainActor observable monitor `isEnabled`, `isCapturing`, `level: Double`, `statusMessage`, `onLevel: ((Double)->Void)?`, `enable() async`, `disable()`, `setSuspended(_:)`; default disabled, explicit enable is the only permission-requesting operation. Inject permission/capture dependencies for lifecycle tests. Native capture callbacks must not inherit MainActor isolation and must discard old-generation data after stop. Parent adds Info.plist/entitlement. Never actually access microphone during testing.

### Task 4: Settings persistence and native integration (parent)

Own Models/Resolver/Store/materialization/binding-copy paths, AppCoordinator/HardwareDeckSession/ActiveAppMonitor, editor/surface/inspector and new LightingSettingsView. Add optional legacy-compatible fields; preserve them in all copy/export/import paths and validate raw data. Route press/status/audio/passive app indicators to originating device; stop on pause/sleep/disconnect/shutdown. Add native page settings, art canvas, safe file import, no-output preview, per-pad effect override and optional microphone controls.

### Task 5: Review and acceptance

- [x] Fresh baseline `swift test` (139 expected), recorded in `/tmp/LaunchDeck-lighting-baseline.log`.
- [x] Focused regression tests for composer/renderer, importer, audio lifecycle, model mapping, companion refresh and action routing. Current full suite: 161 Swift Testing + 25 XCTest pass.
- [x] arm64 and x86_64 app builds pass (`/tmp/LaunchDeck-final-arm.log`, `/tmp/LaunchDeck-final-intel.log`); companion browser tests 8/8; plist lint and `git diff --check` pass.
- [x] Isolated native panel, rainbow animation and pixel-canvas QA with no actions or microphone permission grants (`.agent/workflows/lighting-native-qa.md`).
- [x] Independent review found and fixed stale renderer cancellation, obsolete action status painting and companion animation resets. Regression tests cover each fix; companion HTML contract tests pass.
- [x] README, device, companion and [lighting docs](../../lighting.md) updated; continuity records remaining external hardware and permission acceptance.
