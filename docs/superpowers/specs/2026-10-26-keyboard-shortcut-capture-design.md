# Keyboard Shortcut Capture Design

**Date:** 2026-10-26

## Goal

Let a user assign a Launchpad button shortcut without macOS or another app acting on the pressed keys. Keyboard capture remains active until the user finishes or cancels the capture session. This also applies to shortcut steps in macros, which use the same recorder.

## Current behavior and cause

`ShortcutCaptureView` in `LaunchDeck/EditorView.swift` becomes the first responder and receives `keyDown(with:)` events delivered to its view. It immediately writes each key into the shortcut binding. macOS-reserved combinations such as Command-Tab can be handled before AppKit delivers them to this view, so they trigger their normal system action instead of being recorded. The current recorder has no explicit capture session or Done action.

## Recommended approach

Use a temporary, active Core Graphics session-level event tap while a dedicated shortcut-capture sheet is open. A view-local monitor cannot consume system-level combinations; a permanently registered global shortcut would listen outside the user's editing session and would not provide the requested full keyboard capture. An active event tap can discard keyboard events. Keyboard event taps also require Accessibility authorization, in addition to macOS's separate Input Monitoring permission for listening to keyboard events.

## User flow

1. Clicking a shortcut field opens the capture sheet. The existing shortcut is shown as the pending value.
2. LaunchDeck checks Accessibility authorization when the user starts capture. If it is missing, the sheet shows the existing keyboard-access guidance and an action to request access. The user closes and reopens capture after granting access.
3. LaunchDeck then requests Input Monitoring access on demand. If it is missing or denied, the sheet shows Input Monitoring guidance. The user closes and reopens capture after granting access. The event tap starts only after both permissions are available.
4. While the sheet is active, the tap observes and consumes key-down, key-up, and modifier-change events. A non-modifier key-down updates the pending shortcut using that key's physical key code and the held Command, Option, Control, and Shift modifiers. A later key replaces the pending value; modifier-only presses do not create a shortcut.
5. Clicking **Done** saves the pending value and ends capture. Clicking **Cancel** discards the pending value and ends capture. All keyboard events remain consumed until one of these actions occurs.
6. Closing the sheet or losing LaunchDeck's active status cancels the session and tears down the event tap so capture cannot continue in the background.

## Components and boundaries

- `ShortcutField` owns the capture sheet presentation, supplies the existing `PermissionService`, and commits or discards its pending shortcut through its existing update closure.
- A focused `ShortcutCaptureSession` service owns the event tap lifecycle, Accessibility and Input Monitoring checks, keyboard event decoding, and event suppression. It exposes pending shortcut updates and a distinct permission/failure state to the sheet.
- Pad shortcut fields and macro shortcut fields continue to share the same recorder interface. No shortcut model or profile persistence changes are required.

## Permission and failure handling

The recorder requires both Accessibility authorization for an active event filter and Input Monitoring access to listen to keyboard events. It checks Accessibility through LaunchDeck's existing `PermissionService` and uses its keyboard-access request and system-settings guidance when needed. It requests listening access on demand through `CGRequestListenEventAccess()`. If either permission is denied, the sheet shows the matching action or System Settings guidance and requires the user to reopen capture after authorization. If a tap still cannot be created or macOS disables it, the sheet shows a generic capture failure rather than directing every failure to Input Monitoring. LaunchDeck must not claim capture is active unless an enabled event tap exists. Cancel, Done, window closure, app deactivation, tap disablement, and session deallocation all stop and release the tap.

## Validation

Manually verify that ordinary shortcuts and Command-Tab update the pending value without invoking their normal actions; a subsequent key replaces the pending value; Done saves; Cancel preserves the previous value; permission denial gives guidance; and closing or deactivating the capture UI leaves keyboard input normal. Automated test changes are outside this implementation because the request does not ask for tests.

## Platform reference

- [Apple: CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29?language=objc) documents keyboard event-tap authorization requirements.
- [Apple: CGEventTapOptions](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions) describes active filters that may discard events.
- [Apple: CGRequestListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess%28%29) requests access to listen for keyboard events.
