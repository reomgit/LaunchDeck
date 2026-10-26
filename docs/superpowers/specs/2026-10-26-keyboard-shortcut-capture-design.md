# Keyboard Shortcut Capture Design

**Date:** 2026-10-26

## Goal

Let a user assign a Launchpad button shortcut without macOS or another app acting on the pressed keys. Keyboard capture remains active until the user finishes or cancels the capture session. This also applies to shortcut steps in macros, which use the same recorder.

## Current behavior and cause

`ShortcutCaptureView` in `LaunchDeck/EditorView.swift` becomes the first responder and receives `keyDown(with:)` events delivered to its view. It immediately writes each key into the shortcut binding. macOS-reserved combinations such as Command-Tab can be handled before AppKit delivers them to this view, so they trigger their normal system action instead of being recorded. The current recorder has no explicit capture session or Done action.

## Recommended approach

Use a temporary, active Core Graphics session-level event tap while a dedicated shortcut-capture sheet is open. A view-local monitor cannot consume system-level combinations; a permanently registered global shortcut would listen outside the user's editing session and would not provide the requested full keyboard capture. An active event tap can discard keyboard events, and macOS provides a separate permission API for listening to keyboard events.

## User flow

1. Clicking a shortcut field opens the capture sheet. The existing shortcut is shown as the pending value.
2. LaunchDeck requests Input Monitoring access only when the user starts capture. It creates the event tap only after access is granted.
3. While the sheet is active, the tap observes and consumes key-down, key-up, and modifier-change events. A non-modifier key-down updates the pending shortcut using that key's physical key code and the held Command, Option, Control, and Shift modifiers. A later key replaces the pending value; modifier-only presses do not create a shortcut.
4. Clicking **Done** saves the pending value and ends capture. Clicking **Cancel** discards the pending value and ends capture. All keyboard events remain consumed until one of these actions occurs.
5. Closing the sheet or losing LaunchDeck's active status cancels the session and tears down the event tap so capture cannot continue in the background.

## Components and boundaries

- `ShortcutField` owns the capture sheet presentation and commits or discards its pending shortcut through its existing update closure.
- A focused `ShortcutCaptureSession` service owns the event tap lifecycle, permission check/request, keyboard event decoding, and event suppression. It exposes pending shortcut updates and a clear failure state to the sheet.
- Pad shortcut fields and macro shortcut fields continue to share the same recorder interface. No shortcut model or profile persistence changes are required.

## Permission and failure handling

The recorder requests Input Monitoring access on demand, separate from LaunchDeck's existing event-posting permission. If access is denied, the tap cannot be created, or macOS disables the tap, the sheet shows a short explanation and points to System Settings → Privacy & Security → Input Monitoring. LaunchDeck must not claim capture is active unless an enabled event tap exists. Cancel, Done, window closure, app deactivation, tap disablement, and session deallocation all stop and release the tap.

## Validation

Manually verify that ordinary shortcuts and Command-Tab update the pending value without invoking their normal actions; a subsequent key replaces the pending value; Done saves; Cancel preserves the previous value; permission denial gives guidance; and closing or deactivating the capture UI leaves keyboard input normal. Automated test changes are outside this implementation because the request does not ask for tests.

## Platform reference

- [Apple: CGEventTapOptions](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions) describes active filters that may discard events.
- [Apple: CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29) requests access to listen for keyboard events.
