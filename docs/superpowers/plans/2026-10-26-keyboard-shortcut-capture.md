# Keyboard Shortcut Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture and consume keyboard shortcuts for Launchpad buttons and macro steps until the user clicks Done or Cancel.

**Architecture:** Add a short-lived `ShortcutCaptureSession` that checks Accessibility and Input Monitoring access and owns an active Core Graphics session event tap. Present it through a capture sheet shared by all `ShortcutField` instances; only Done commits the pending shortcut, while Cancel and focus loss stop capture without changing the stored value.

**Tech Stack:** Swift 6.2, macOS 26+, SwiftUI, AppKit, Core Graphics.

## Global Constraints

- macOS deployment target remains 26.0; add no package dependency.
- Check Accessibility authorization and request Input Monitoring only after the user opens shortcut capture; never report capture active unless both permissions are available and an event tap was successfully created and enabled.
- If Accessibility is missing, show `PermissionService.settingsGuidance` and an action using `PermissionService.requestAccess()`; require reopening capture after authorization. If Input Monitoring is missing, show its matching guidance and require reopening capture after authorization.
- Consume keyboard key-down, key-up, and modifier-change events only during capture. Keep the Done and Cancel controls available by mouse.
- Stop and release the event tap on Done, Cancel, sheet dismissal, app deactivation, tap failure, and session deallocation.
- Keep Launchpad button shortcuts and macro shortcuts on the same recorder; do not change shortcut model or profile persistence.
- Do not add or run automated tests for this task; the user did not request testing or verification.

## File Map

- Create `LaunchDeck/Views/ShortcutCaptureSession.swift` for Accessibility/Input Monitoring checks, active event tap lifecycle, captured shortcut decoding, and permission/tap failure state. The `Views` directory is excluded from the Swift package core target and included in the app target.
- Modify `LaunchDeck/Views/PadInspector.swift` so `ShortcutField` supplies the existing `PermissionService`, opens a sheet, stages its pending value, commits only on Done, cancels without updates, and ends capture when LaunchDeck resigns active.
- Modify `LaunchDeck/EditorView.swift` to remove the old view-local `ShortcutRecorder` and `ShortcutCaptureView`, which are replaced by the session-based recorder.

---

### Task 1: Add the bounded keyboard capture session

**Files:**
- Create: `LaunchDeck/Views/ShortcutCaptureSession.swift`

**Interfaces:**
- Produces `@MainActor @Observable final class ShortcutCaptureSession`.
- Expose `private(set) var pendingShortcut: Shortcut?`, `private(set) var state: State`, `func begin(initialShortcut: Shortcut, accessibilityTrusted: Bool)`, `func finish() -> Shortcut?`, and `func cancel()`.
- `State` distinguishes idle, capturing, Accessibility-required, Input-Monitoring-required, and a generic event-tap failure.
- The view refreshes `PermissionService` before calling `begin`. The session checks Accessibility first, then checks/requests Input Monitoring, then starts the tap.
- The view calls `begin` when the sheet appears, reads `pendingShortcut` and `state`, calls `finish` only from Done, and calls `cancel` from Cancel or dismissal.

- [ ] If `accessibilityTrusted` is false, set the Accessibility-required state and do not request Input Monitoring or create a tap.
- [ ] Check `CGPreflightListenEventAccess()` when capture begins; if access is missing, call `CGRequestListenEventAccess()` and set the Input-Monitoring-required state if access remains denied.
- [ ] Create a `.cgSessionEventTap` active filter at `.headInsertEventTap` for `.keyDown`, `.keyUp`, and `.flagsChanged`; add its run-loop source to the main run loop and enable it before setting state to capturing.
- [ ] Retain both the tap and run-loop source for the session lifetime. If tap creation, source creation, or enabling fails, remove any partial resources and publish a clear failure message.
- [ ] In the callback, return `nil` for each keyboard event while capture is active so the event is consumed. On key-down, ignore modifier-only key codes; otherwise update `pendingShortcut` with the physical key code and currently held Command, Option, Control, and Shift flags. Convert the event to `NSEvent` for `charactersIgnoringModifiers`, map Escape to `ESC`, Tab to `TAB`, Return to `RETURN`, keypad Enter to `ENTER`, and use `Key <keyCode>` for missing or nonprinting labels.
- [ ] Handle tap-disabled notifications as a generic capture failure, stop and invalidate the tap, and do not leave an inactive tap represented as an active capture state.
- [ ] Implement `finish()` to return the pending value only while capture is active, then stop resources. Implement `cancel()` as an idempotent stop that clears transient state. Add `@MainActor deinit` cleanup as a final lifecycle guard.
- [ ] Review this new file for main-thread ownership: install the event tap source on the main run loop, update observable state on that run loop, and keep the callback limited to flags, key code, label, and state changes.

### Task 2: Replace the view-local recorder with a capture sheet

**Files:**
- Modify: `LaunchDeck/Views/PadInspector.swift`
- Modify: `LaunchDeck/EditorView.swift`

**Interfaces:**
- `ShortcutField` retains its existing `shortcut: Shortcut` and `update: (Shortcut) -> Void` inputs.
- `ShortcutCaptureSession` from Task 1 supplies the pending shortcut and capture state.
- The sheet receives Done and Cancel closures; Done passes the session's returned shortcut to the existing `update` closure, and Cancel never calls `update`.

- [ ] Give `ShortcutField` `@Environment(AppCoordinator.self)` access to `coordinator.permissions` while preserving its `shortcut` and `update` inputs.
- [ ] Change `ShortcutField` from a permanently focused `ShortcutRecorder` to a button that displays the current shortcut and opens a sheet with a `ShortcutCaptureSession`.
- [ ] On sheet presentation, call `coordinator.permissions.refresh()` and then `begin(initialShortcut:accessibilityTrusted:)`. Keep the current shortcut visible as the initial pending value; each later non-modifier key-down replaces it.
- [ ] Add a pending-shortcut preview and visible state text. For Accessibility-required state, show `PermissionService.settingsGuidance` and a button that calls `coordinator.permissions.requestAccess()` before closing capture. For Input-Monitoring-required state, show System Settings → Privacy & Security → Input Monitoring guidance. For a tap failure, show a generic failure. Keep Cancel available and do not claim capture is active. Reopening the sheet after granting permission is required.
- [ ] Add a Done button that calls `finish()`, updates the binding only when a shortcut is returned, and dismisses the sheet. Add a Cancel button that calls `cancel()` and dismisses without updating.
- [ ] Observe `NSApplication.didResignActiveNotification`; cancel and dismiss capture when LaunchDeck loses focus. Also stop from sheet dismissal and session cleanup so no path leaves the event tap running.
- [ ] Remove `ShortcutRecorder` and `ShortcutCaptureView` from `LaunchDeck/EditorView.swift`, including the old first-responder `keyDown(with:)` implementation.
- [ ] Confirm the existing pad shortcut field and `StepEditor` macro shortcut case still use the same `ShortcutField`, so both flows gain the new Done/Cancel capture behavior.

### Task 3: Review the implementation against the approved behavior

**Files:**
- Review: `LaunchDeck/Views/ShortcutCaptureSession.swift`
- Review: `LaunchDeck/Views/PadInspector.swift`
- Review: `LaunchDeck/EditorView.swift`

- [ ] Inspect the source diff to confirm that only the approved capture flow is changed, model persistence remains untouched, and the event tap has every documented stop path.
- [ ] Confirm that the sheet cannot commit on Cancel, dismissal, focus loss, or permission failure, and that Done commits only the pending shortcut.
- [ ] Do not run build or test commands for this task; no verification run was requested.
