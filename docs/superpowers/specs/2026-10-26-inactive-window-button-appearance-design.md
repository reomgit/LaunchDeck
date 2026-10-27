# Keep LaunchDeck Controls Bright When the Window Is Inactive

## Context

macOS gives SwiftUI an inactive appearance when a window is not focused. SwiftUI styles can use that environment to dim controls, including LaunchDeck's custom glass pads and hosted titlebar controls. This presentation change can make enabled controls look disabled.

## Goal

Keep LaunchDeck's editor controls visually active while its window is unfocused, without changing which actions are enabled or how they behave.

## Design

Override `EnvironmentValues.appearsActive` to `true` for the editor's SwiftUI content and the separately hosted titlebar status controls. This limits the appearance override to LaunchDeck's controls and allows standard inactive-window treatment to remain elsewhere in macOS.

The override affects appearance only. Existing `.disabled(...)` conditions continue to determine whether an action can be used. The native window chrome remains managed by macOS.

## Acceptance Criteria

- Enabled editor buttons and Launchpad pads retain their active visual appearance when the LaunchDeck window loses focus.
- Hosted titlebar controls retain their active visual appearance when the window loses focus.
- Controls disabled by existing app rules remain disabled.
- Refocusing the window does not change control behavior or assignment state.

## Scope

Only the editor appearance environment and its separately hosted titlebar status controls need changes. No coordinator, profile, device, or action behavior changes are required.

## Verified follow-up — 2026-10-27

The environment override alone did not retain Liquid Glass tint in the running inactive editor. Preserve the existing native `.glassEffect`, `GlassEffectContainer`, shapes, and window chrome. Add a 60%-opacity color backdrop behind each glass pad and the Novation tile so their colors remain visible when macOS suppresses the glass tint. This is a backdrop for real glass, not a replacement material; native glass can still adapt to window focus. Keep inherited opacity and existing disabled rules unchanged. Allow window-activation clicks in the editor and hosted titlebar controls.

Restore regular app activation while an editor or About window is open, accessory activation after the last closes, and editor reopening/restoration from the Dock. Keep the menu bar entry available.

Verification: Debug Xcode build succeeded. In the relaunched signed app, native UI inspection with Finder active confirmed colored glass pads remain visible; button accessibility and assignments were preserved. No application test suite was run for this presentation change.
