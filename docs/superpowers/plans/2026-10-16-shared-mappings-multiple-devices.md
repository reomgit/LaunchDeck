# Shared mappings and multiple Launchpads Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development and dispatching-parallel-agents for independent UI and transport tasks. Preserve all pre-existing edits; do not commit unrelated work.

**Goal:** Stable shared mappings with protected model overrides, automatic simultaneous device support and the three requested UI fixes.

**Architecture:** Keep stored layouts and introduce an explicit profile override flag. Route simultaneous MIDI connections by unique device ID and generation, with coordinator-owned per-device navigation/renderers. Keep a selected device facade for existing status/editor consumers.

**Tech Stack:** Swift 6.2+, macOS 26+, SwiftUI/AppKit, CoreMIDI, Swift Testing/XCTest.

**Spec:** `docs/superpowers/specs/2026-10-16-shared-mappings-multiple-devices-design.md`

## Global Constraints

- Preserve the native window, Liquid Glass and physical pad arrangement.
- Preserve all existing dirty-checkout edits and stored model layouts.
- Shared mapping is default; enabling model-specific layouts requires a warning.
- No system packages, external publication or real target actions during QA.

## Review Focus

- Two identical hardware models must remain distinct by endpoint unique ID.
- Delayed old-generation input and LED restores must not reach a reconnected unit.
- Imported/legacy hidden model layouts must be validated and preserved.
- Disabling overrides must immediately restore shared assignments everywhere.
- Mouse selection must work on empty and assigned pads and leave drag usable.

### Task 1: Native UI bug fixes

Own `LaunchDeck/Views/LaunchpadSurface.swift`, titlebar controls in `LaunchDeck/LaunchDeckApp.swift`, and relevant native QA. Investigate event hit testing before fixing. Make selection a visible blue outline outside the glass surface; preserve drag/drop. Render disabled bindings neutrally regardless of stored color. Label the switch Pause and keep a direct isPaused binding. Verify with a native temporary-config app and report reproduction/evidence.

### Task 2: Simultaneous MIDI transport

Own `LaunchDeck/Services/MIDIService.swift`, new `Core/MIDIDeviceConnections.swift`, and focused transport tests. Add `MIDIDeviceEvent(deviceID: Int32, event: PadEvent)`, `connectedDevices: [MIDIDeviceChoice]`, `onDevicePadEvent`, `onDevicesChanged`, `sendSysEx(_:to:)`, and `generation(for:)`. Keep existing selected-device facade/callbacks for compatibility. Connect every available pair, disconnect only removed endpoints, restore Live mode on every stopped connection, tag source callbacks by unique connection token. Test the real connection bookkeeping with injectable endpoint/transport closures or a pure routing component consumed by MIDIService. First observe focused failing tests, then pass them.

### Task 3: Shared mappings, protected overrides, and coordinator integration

Own model/resolver/store/cache/coordinator and `Views/DeviceWorkflowControls.swift`. Add profile override flag with backward-compatible decode; shared effective layouts project Mini controls, raw layouts remain separately validatable. Add explicit enable/disable override methods and UI warning. Edit shared controls in base layout, reject unsupported Pro-only edits until overrides enabled. Maintain per-device runtime navigation, held pads and LEDRenderer, route input/output using Task 2 APIs, select editor hardware independently from connecting it. Test shared model changes, explicit overrides, disabled metadata, navigation isolation and reconnect behavior. Update existing tests that explicitly exercise the intentionally replaced independent-layout default to enable overrides first.

### Task 4: Integration and acceptance

- [x] Baseline: `swift test` (121 tests passed before edits).
- [x] Observed focused failures for mapping loss, multi-device routing, dormant validation, deletion rollback and navigation observation, then passing regressions.
- [x] Full `swift test`: 139 tests pass (25 XCTest + 114 Swift Testing); `/tmp/LaunchDeck-final-tests.log`.
- [x] Final arm64 workspace and x86_64 native builds pass with signing disabled; `/tmp/LaunchDeck-2026-10-16-{workspace-build,intel}.log`.
- [x] Native pointer selection, blue outline, disabled neutral face and pause off/on/off verified in controlled baseline/fixed comparison. Latest build initial Shared/Pause state inspected. Further warning-dialog/preview transitions blocked by native automation bridge failure; physical multi-device and manual drag acceptance remain unverified. Plist lint and `git diff --check` pass.
- [x] Independent review's three findings fixed; scoped re-review has no residual actionable issues. Same-ID replacement cancels execution, raw stored indices validated, unsafe cross-profile deletion rolls back with feedback.
- [x] README/device documentation and `.agent/CONTINUITY.md` updated with behavior, verification and limitations.

Execution uses the existing authorized dirty checkout on `codex/desktop-workflows`; no reset, stash, worktree copy or unrelated commit. Native macOS frameworks require native Xcode/Swift verification rather than Linux containers.
