# Immediate settings and automatic app profiles

Approved by the user on 2026-10-26. Execute in the existing feature checkout.

## Contract

- Follow the focused application's profile, falling back to Global. Edits save and refresh the effective runtime immediately; inspecting another profile never activates it.
- Physical buttons select controls while LaunchDeck is focused. Preserve existing execution behavior unless an outside-editor failure is reproduced.
- Remove Activation from the editor. Identify the editing and in-use profiles, and explain the physical editing behavior.
- Put temporary overrides under Tools → Advanced → Profile Override, with Resume Automatic Switching and visible override status. Mirror this organization in the menu bar and companion.
- Overrides last until resumed or restarted. Ignore legacy saved pins without changing the configuration schema or profile contents.

## Tasks and verification

1. Test-first: temporary overrides, legacy pins, deletion and undo; preserve immediate edits. Inject the existing app monitor for deterministic focus and routing tests.
2. Update native and companion controls and status. Test companion synchronization, override requests, and return to automatic mode.
3. Verify two app profiles → Global switching, inherited live edits and undo, multiple model sessions, and keyboard/launch routing through the coordinator.
4. Run the full Swift suite, companion client tests, and signed native build. Inspect the running signed UI and preserve user configuration. Actual Mini presses require the user; record their result separately from injected-event tests.

## Defaults

The sidebar remains an editor selection. Advanced overrides explicitly suspend automatic switching, never persist, and are not part of configuration undo. Preserve the companion API's Auto/Manual mode values and /api/activate endpoint for compatibility; present clearer names in its UI.
