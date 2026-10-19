# Shared mappings and multiple Launchpads

## Intent and authority

The user requests automatic model recognition, stable mappings across model changes, protected model-specific settings with a warning, simultaneous Launchpads, and fixes for mouse selection, disabled colors and pause presentation. On 2026-10-16 the user selected “Yes—shared mappings, protected model overrides.” Earlier workspace continuity records delegated implementation choices and permission to work atop this dirty checkout. Preserve the existing native window, Liquid Glass and physical pad arrangement. Broader action/lighting brainstorming remains an active follow-up; this delivery addresses the user's concrete steering.

## Mapping behavior

Profiles use the existing Mini-compatible 80-control layout as their shared mapping. The 64 grid controls and shared top/right controls retain their indices across physical models; virtual decks project the 64 grid controls. Changing the displayed model does not change this mapping. Pro-only controls require model overrides. Model overrides are off by default and locked in the UI. Enabling them requires a warning that models can then have different assignments. Existing model layouts remain stored and can be recovered by enabling overrides. Disabling overrides preserves them and returns to shared mappings. Model switching itself is a harmless preview and needs no warning. Schema 3 remains readable using an optional persisted profile field, and validation must still inspect every stored layout independently.

## Hardware behavior

CoreMIDI recognizes and connects every supported Launchpad source/destination pair, including two units of the same model. Each connection has a unique ID and a connection generation. Input is tagged with both so disconnected devices cannot dispatch late events. Each device owns navigation, held controls and LED rendering; mappings/profile activation are shared. The editor follows a selected connected device automatically; a deliberate disconnected model preview is available. Device selection chooses which deck the editor shows, not which device is allowed to connect. A disconnect affects only its device, conservatively cancels execution and restores remaining devices. Pause/session suspension/quit affect all devices, and session resume repaints each connected device. Existing scripts remain serialized by the common action executor.

## UI fixes

Mouse clicks select assigned and unassigned pads without executing actions, dragging remains possible, and selection has a visible blue outline above glass. Disabled assignments have no color in editor, companion or hardware, regardless of a stored color or later color edits. The titlebar switch is visibly labelled Pause, off when running (including startup), on when paused, and shares state with menu commands.

## Verification

Run existing Swift tests and focused regressions for shared/overridden layouts, old configuration round trips, device isolation, stale generations, independent navigation, disabled presentation and pause cancellation. Build the native macOS app for arm64 and x86_64, run plist and whitespace checks, then inspect native mouse selection, disabled appearance and switch interaction. Use temporary configuration for UI QA. Real multi-device USB/LED acceptance is conditional on hardware availability and must be reported honestly.
