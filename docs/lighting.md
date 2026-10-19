# Reactive lighting and LED art

LaunchDeck keeps pad assignments shared across Mini MK3, Launchpad X and Pro MK3 models unless model-specific layouts are explicitly enabled. Lighting follows the same shared mapping and page inheritance rules. Model-specific overrides remain stored while locked; enabling or unlocking them requires accepting the warning in **Tools → Model-Specific Layouts**.

Open **Tools → Lighting and LED Art** to configure a page. Ambient effects include breathing, rainbow, scanner and audio meter. Press effects can be set per pad and include glow, ripple, cross and sparkle. A pad can suppress its inherited press animation. Brightness, effect color and speed are configurable. Status lights report running/frontmost state only for an assigned app-launch action, and action feedback reports the result of that pad's active action. They do not claim that a target app accepted a shortcut.

LED pixel art is an optional 64-color RGB image attached to a page. Paint the 8×8 canvas or import a PNG/JPEG; imports are center-cropped to a square and sampled into the physical grid's orientation. Artwork and settings follow a page when profiles are copied or exported. A disabled pad remains dark through art, ambient effects and feedback.

**Preview Press** and the editor's animated preview never execute the selected action or send MIDI. Real per-device output starts only when the deck is active. Pausing or suspending the session turns output off and suspends microphone capture. The phone/tablet companion follows the virtual deck and refreshes animated colors more frequently while effects are running.

## Microphone privacy

Audio meter lighting is opt-in. LaunchDeck requests microphone access only when **Enable Microphone** is pressed in the lighting panel; importing a profile or selecting an audio preset cannot enable capture. The app derives a loudness level in memory, does not save or transmit audio, stops capture when disabled, paused, suspended or shut down, and clears stale levels after input loss or permission revocation. macOS microphone access and its normal permission prompt are still required on the user's machine.

Core lighting composition, cancellation, persistence, importer limits and audio lifecycle have unit coverage. Isolated native UI verification covers painting and a live rainbow preview without hardware or microphone access. Actual USB LED rendering, attached-device model recognition and microphone behavior require the user's devices and macOS permissions for acceptance.
