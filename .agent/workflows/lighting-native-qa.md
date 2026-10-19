# Reactive lighting native QA — 2026-10-16

## Isolation and scope

Native QA used `/tmp/LaunchDeck-lighting-qa-source`, `/tmp/LaunchDeck-lighting-qa-derived`, bundle ID `dev.launchdeck.LightingQA`, and `ProfileStore(directory: /tmp/LaunchDeck-lighting-qa-config)`. Only the temporary AppDelegate was changed: it creates the fixture, omits `coordinator.start()` (no MIDI/action/session monitoring), opens the Lighting sheet, and in the diagnostic rebuild writes read-only state samples every 0.2 seconds. No production source, user profiles, permissions, external services, or other app processes were changed. Both arm64 fixture builds passed; logs are `/tmp/LaunchDeck-lighting-qa-build.log` and `/tmp/LaunchDeck-lighting-qa-diagnostics-build.log`.

Fixture: Global Lighting QA / Home, Mini MK3. Index 0 blue QA Shortcut (⌘C); index 1 Disabled QA with deliberately stored red color; index 79 green Outer QA (⌘V). Initial page lighting defaults to Glow/None, full brightness, no artwork.

## Native checks

- Tools → Lighting and LED Art… opens the native sheet. Both columns and controls are readable, with an entire 8×8 artwork canvas. Accessibility exposes exactly 64 LED pixel buttons: top-left LED pixel 57, bottom-left LED pixel 1. The audio section can be reached by normal scroll.
- Clicking top-left paints one green pixel and enables Clear Art. Reading the isolated JSON confirms a 64-pixel grid with index 56 green (`26,99,44`); index 0 retains blue, index 1 black, other blank cells black. This proves the top/bottom canvas orientation and local persistence.
- Fill paints all 64 raw artwork cells green and persists them. The artwork canvas shows raw stored pixels (including the disabled cell), rather than the composed output. Clear Art removes gridArtwork and disables Clear Art again. Reopening the panel keeps saved settings; a diagnostic app restart also loads saved settings.
- Fixture actions, labels, stored binding colors, and outer binding are unchanged through paint/fill/clear. JSON still contains ⌘C at index 0, disabled at index 1, ⌘V at index 79. Per-pad Ripple is the only intentional binding metadata change.
- Selecting pad 1 opens Control 1, keeps action ⌘C and exposes Press animation. Menu options: Page Default, Glow, None, Ripple, Cross, Sparkle. Selecting Ripple persists and reopening the inspector shows Ripple.
- Ambient picker exposes None, Breathe, Rainbow, Scanner, Audio Meter. Selecting Rainbow persists across panel close/reopen. Two active-window screenshots in the CUA transcript show clearly different rainbow positions across the full grid, while Disabled QA stays neutral/unlit and Outer QA remains green. Preview artwork does not create actions on unassigned controls; AX keeps those controls Unassigned.
- Preview Press was clicked with index 0 selected and Ripple override set. No action permission prompt, action dispatch feedback, or label/action mutation appeared. The test fixture never starts action/hardware monitors. The short ripple transient itself was not separately captured, so visual ripple geometry is not claimed from this QA.
- Audio Meter selection exposes Enable Microphone, Microphone off, Microphone loudness=0. Scrolling shows these fully. No OS permission prompt occurred; Enable Microphone was never pressed. A fresh diagnostic app launch with the saved Audio Meter preset still showed Microphone off and zero loudness.
- Pause on/off updates native AX to Paused/on and then Searching for Launchpad/off with Running help. There is no connected Launchpad. No real actions or hardware/microphone acceptance was tested.

## Active-window diagnostics and visual context

The initial series of main-window screenshots after sheet dismissal had inactive traffic lights/sidebar and gray native glass faces, even for enabled fixture bindings. AX window Raise and pause/resume did not visibly restore tint. One coordinate click failed with `noWindowsAvailable`; a fresh bundle bind worked. `cua.computer.launch_app` is not available on this Mac runtime. The first attempted bind also happened before the initial executable finished building; it returned `kLSNoExecutableErr` and was retried after build success.

The instrumented temporary rebuild/relaunch produced an active, key main window with colored traffic lights and blue selected sidebar, and positive animated colors. This distinguishes the later successful native rendering from the earlier inactive screenshots; inactive glass tint is a plausible explanation, but no claim is made that inactive-window lighting remains visible.

Read-only diagnostics at two monotonic samples about 0.2 seconds apart:

| Field | t=17992.88587975 | t=17993.084386458333 |
| --- | --- | --- |
| isPreviewing / frame count | true / 80 | true / 80 |
| index 0 RGB | 127,0,55 | 127,0,33 |
| disabled index 1 RGB | 0,0,0 | 0,0,0 |
| index 56 RGB | 0,127,24 | 0,127,46 |
| outer index 79 RGB | 24,127,70 | 24,127,70 |
| paused / suspended | false / false | false / false |
| selected profile / page / model | Global Lighting QA / Home / miniMK3 | same |
| brightness / ambient / artwork count | 1 / rainbow / 0 | same |
| NSApp active / key window / main window | true / true / true | true / true / true |

The isolated saved config independently reports brightness=1 and ambientEffect=rainbow. Diagnostics at t17973.08449 and t17973.28359 on the saved Audio Meter launch showed index0=30,90,127, index1=0,0,0, index56=0,0,0, index79=24,127,70, previewing=true, frameCount=80, paused=false, suspended=false, brightness=1, ambient=audioMeter, artworkCount=0, NSApp active=true, mainWindow=true, keyWindow=false (sheet open).

Full samples: `/tmp/LaunchDeck-lighting-qa-config/diagnostics.txt`. Screenshots and full native AX evidence are inline in this agent’s CUA transcript; no screenshot files were exported. The active rainbow screenshots show disabled native glass as a neutral gray face, with the composed color confirmed black by diagnostics.

## Limits and cleanup

Real USB LED timing, microphone-device capture/permissions, visual ripple transient geometry, image import dialogs, and inactive-window color visibility remain unverified. No broad completion claim follows from native QA alone. Parent integration owns full tests, both architecture builds, and source review.

The isolated QA app was quit through its bound native CUA app using Command-Q at the end. No user workspace app was closed.

## Requested model-specific warning follow-up

Reopened only the isolated QA app for an additional Tools → Model-Specific Layouts → Cancel acceptance check. CUA twice rejected actions with “The user changed [isolated app path]. Re-query the latest state …”. After the first rejection, fresh AX reported Brightness 19% / 0.1945333845628415, a change not made by this agent; the earlier diagnostic/rainbow proof above was at brightness 1. The refreshed Done action succeeded. Tools exposes Model-Specific Layouts, but selecting it triggered the second guard; fresh AX showed the menu dismissed, still Shared. The confirmation warning and Cancel behavior were therefore not reached and remain unverified. No retry loop or Unlock action occurred. The isolated app was quit again through its bound CUA app.

## Workspace follow-up: 2026-10-16 13:57 UTC

The rebuilt actual workspace app detects `LPMiniMK3 MIDI Out` through CoreMIDI and auto-follows Mini MK3. Tools lists one connected device (unique ID 2,070,438,277). User confirms their Mini is connected, superseding earlier USB-inventory absence. A mouse click opens Control 58 in the inspector. Tools → Model-Specific Layouts displays “Enable Model-Specific Layouts?” and explains saved layouts/shared mappings; Cancel successfully returns to Shared. No unlock, mapping edit or permission grant occurred. Physical press/LED observation has been requested from the user; multiple simultaneous units remain unverified on physical hardware.

## Physical Mini MK3 and target-app acceptance

User confirms physical press light reaction. A temporary diagnostic build signed with the same designated requirement as the user's Xcode app recorded the top-left pad at zero-based index56, normal press/release, assigned action, editor=false, correct TextEdit target, and both AX and event-post permissions true. Native result was “Untitled: dispatched.” TextEdit's Copy menu initially disabled because no text was selected. After selecting existing “Test text” through native UI, user pressed the pad with TextEdit active and confirmed the paste returned “Test text.” This verifies actual Mini input, LED reaction and target-app keyboard dispatch. All temporary dispatch logs were removed afterward. The microphone and multiple physical units remain untested.
