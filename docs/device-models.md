# Device layouts and MIDI protocol

LaunchDeck automatically recognizes Launchpad Mini MK3, Launchpad X and Launchpad Pro MK3. Profiles use shared mappings by default, projected onto each model's available controls (64 grid controls for the Virtual Deck). Previewing another model keeps common assignments. Application profiles inherit Global mappings until locally overridden; Manual profiles remain independent of other profiles.

Tools → Model-Specific Layouts requires a warning before unlocking independent model mappings. Existing layouts are preserved and reactivated; new model layouts start from the shared mapping. Turning it off returns to shared mappings without deleting saved layouts. Pro-only controls require model-specific layouts. The model picker is a harmless preview; Tools → Auto-Detect Model resumes following the selected connected unit.

The Mini's existing indices remain unchanged: 0–63 are the grid (bottom row first, left to right), 64–71 the top controls (left to right), and 72–79 the right controls (top to bottom). X uses the same positions. Pro additionally has indices 80–87 down the left edge, 88–95 across the inner bottom row, 96–103 across the outer bottom row, and 104 for Shift at the upper left. Setup is not assigned in the documented programmer map, and the logo is an LED rather than an assignable control.

Copy Layout previews the assignments mapped by physical row and column. Grid indices therefore remain stable when copying to the virtual layout. Assignments without a target position are listed before copying; the source layout remains available. Copying replaces the target layout, including its pages and folders, so review the preview first.

## Persistence and portable packages

Configuration schema 3 retains `pages`, `folders`, `pageOrder`, and `folderOrder` as the shared/Mini compatibility fields and stores additional model layouts in `modelLayouts`, keyed by model name. The optional `modelOverridesEnabled` profile flag defaults to false when absent. Dormant layouts are validated and retained in exports, including artwork and fresh imported script consent IDs. Shared virtual edits do not truncate the physical perimeter controls. Schema 1 and 2 are validated before migration and written only after creating an untouched `profiles.v1.backup.json` or `profiles.v2.backup.json`. A conflicting backup prevents migration instead of overwriting an earlier original.

Profile package schema 2 declares configuration schema 3 and the included device models. Exports materialize application inheritance independently for every model and include all referenced artwork; importing assigns a fresh profile ID, fresh local artwork IDs, and fresh script consent IDs. Repeated uses of the same script ID share a replacement within one import; separate imports require separate local enabling. The legacy package schema 1 remains readable. Local script approvals and Keychain secret values are not profile fields.

## Hardware connection

Every supported source/destination pair connects simultaneously, including identical models. Sources and destinations must belong to the same CoreMIDI device and entity. Programmer control uses the model's MIDI interface; DAW and DIN interfaces are excluded. The editor's device selector retains a source endpoint's CoreMIDI unique ID and changes only the displayed unit. A missing explicitly selected device does not silently switch the editor to another controller; other connected devices remain active.

Each unit owns navigation, held pads, connection generation and its LED renderer. Incoming callbacks carry an opaque lifetime token mapped to the original device and generation, so old-source events cannot use a newly selected or reconnected unit. Targeted output additionally verifies the connection generation. A disconnect or replacement cancels active execution conservatively. Stopping restores every connected device to Live mode; pause/session suspension applies to all units.

Reconnect repaint sends the full model surface, including off entries, to clear unknown hardware LED state. Flash restorations are invalidated when the layout, model, or repaint generation changes.

Protocol references inspected on 2026-10-06:

- [Launchpad X surface and LED reference](https://userguides.novationmusic.com/hc/en-gb/articles/24001475492498-Controlling-the-Launchpad-X-surface), updated 2025-01-21.
- [Launchpad Pro MK3 programmer reference](https://fael-downloads-prod.focusrite.com/customer/prod/s3fs-public/downloads/LPP3_prog_ref_guide_200415.pdf), programmer surface diagram on page 19 and mode/RGB commands on pages 18 and 12–13.
- [Launchpad Pro MK3 hardware overview](https://userguides.novationmusic.com/hc/en-gb/articles/25494505681042-Launchpad-Pro-MK3-hardware-overview), updated 2025-04-23, used to name the physical controls.

Protocol tests establish message mapping and encoding, not physical compatibility. Mini, X, and Pro LED/press/hotplug behavior still needs verification with actual controllers.
