# Reactive lighting and LED artwork

## Intent and scope

Continue the original action/artwork/reactive-animation goal after the shared-mapping and multi-device delivery. Existing native actions already cover app/file/folder/web launching, shortcuts/text, mixed macros, shell/AppleScript and manifest/HTTP extensions. This stage supplies launchpad-specific expressive behavior: configurable press animations, idle animations, execution/application status, an 8×8 pixel-art editor and image import, and optional microphone-loudness reactive lighting. Per-button desktop artwork remains available. Prior user delegation of implementation choices remains active; no new human answer is inferred from automatic goal continuation. The preceding goal turn made concrete implementation and verification progress.

## Data and compatibility

`DeckPage.lighting: LightingSettings?` is optional and defaults to nil for legacy pages. `PadBinding.pressEffect: PressEffect?` optionally overrides the page press effect. `ResolvedLayout.lighting` is a nonoptional resolved setting with static defaults. Application page overrides inherit Global lighting when their lighting is nil. Shared/model-specific mapping semantics, dormant layouts, portable artwork and script consent behavior remain intact. Copying or rekeying bindings preserves pressEffect; copying/exporting/materializing pages preserves lighting. Validate raw dormant settings too.

`LightingSettings` fields: pressEffect (.glow default, .none/.ripple/.cross/.sparkle), ambientEffect (.none default, .breathe/.rainbow/.scanner/.audioMeter), brightness (finite 0...1, default 1), speed (finite 0.25...3, default 1), accentColor (default .blue, 7-bit RGB), gridArtwork (nil or exactly 64 7-bit RGB pixels), showsActionStatus (true), showsApplicationStatus (true). All settings are Codable/Hashable/Sendable. No new schema number is required for optional page/binding fields.

## Rendering

Compose base binding colors and optional grid artwork, idle motion, passive app state, bounded press transients, then action status. Explicitly disabled controls always finish black; pause/session suspension/stop finish black and cancel animation tasks. Artwork can color unassigned controls without creating actions. Grid pixels use existing pad indices: image top-left maps to pad index 56, bottom-left to 0. Top/right/Pro-only controls retain their normal bindings.

The pure frame composer is deterministic at an injected monotonic time. Renderer runs at most 30 frames/second only while motion/transients/status require it, batches changed LEDs via existing SysEx, bounds simultaneous press events, restores the exact base frame after effects, and cancels obsolete state across layout/model/pause/repaint/stop changes. Weak task ownership must not retain a renderer indefinitely. Per-device generation checks from the previous delivery also guard all animated output. A no-output preview renderer drives native preview; editor clicks select and may preview an effect but never execute an action.

Action running/success/failure colors are transient indicators; success still means dispatched, not accepted by another app. Passive app indicators only describe an actual launch-app binding's matching running/frontmost application; a missing app or an arbitrary keyboard shortcut must not claim a state it cannot know.

## Artwork workflow

Tools → Lighting and LED Art exposes page effects/brightness/speed/accent/status controls, a 64-pixel paint canvas, a paint color, image import and clear-art. Existing app button styles/frame stay intact. PNG/JPEG import rejects oversized/malformed/multiframe inputs, honors image orientation, downsamples to an 8×8 grid, preserves top/bottom orientation and 7-bit RGB limits, and does not modify actions/labels/outer controls. Canvas colors live directly in page settings, so they travel in portable profiles without file dependencies. An explicit preview press needs no hardware or action permissions.

## Audio privacy and lifecycle

Microphone capture starts only through an explicit in-app Enable Microphone button, with the normal OS authorization flow. No OS permission is granted by automation. Profile import, selecting an audio preset, app launch and hardware connection cannot start capture. Compute bounded RMS loudness samples only; no audio files or raw audio leaves the callback. Off/denied/no input are visible states. Pause, session suspension and shutdown stop capture; resume may restart only a user-enabled session with already authorized access. Add the microphone usage string and audio-input entitlement for hardened builds. Tests use synthetic PCM and injected permission/capture dependencies, never real recording.

## Acceptance

Deterministic tests prove geometry/time evolution, layer restoration, disabled black, brightness/ranges, bounded events, no post-stop output, per-device isolation, artwork orientation/validation, legacy decode/inheritance/copy/export, app-state truthfulness and audio opt-in/cancellation. Run the complete suite and both native architecture builds. Native QA uses isolated configuration and verifies settings/preview/canvas without invoking real target actions or microphone access. Real USB light timing and actual microphone-device acceptance remain explicitly unproven without devices/consent; do not claim overall goal complete solely from software tests.
