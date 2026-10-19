# LaunchDeck

LaunchDeck turns a Novation Launchpad into an app-aware macOS shortcut controller.

It is a native SwiftUI menu-bar utility for macOS 26 or later. It supports Launchpad Mini MK3 and Launchpad X (80 controls), Launchpad Pro MK3 (105 controls), and an independent 64-control phone/tablet browser deck. Features include application-aware profiles, folders/pages, mixed-action macros, scripts, installable extensions, community content, and portable profiles with artwork.

## Requirements

- macOS 26.0 or later
- Xcode with Swift 6.2 or later (native builds verified with Xcode 27 beta)
- A supported Novation Launchpad connected by USB, or a paired browser companion
- Accessibility permission for keyboard/text actions; resource opening and navigation work without it

LaunchDeck uses the device's Programmer mode while connected and restores Live mode when it quits. Screen recording is not required. AppleScript actions may require Automation permission for their chosen applications.

## Run from source

```sh
git clone https://github.com/reomgit/LaunchDeck.git
cd LaunchDeck
open LaunchDeck.xcodeproj
```

Choose the `LaunchDeck` scheme and run it. Grant keyboard access when LaunchDeck asks: System Settings → Privacy & Security → **Device Control and Data Access** on macOS 27, or **Accessibility** on macOS 26. Enable the same app build you run; switching between unsigned builds and an Xcode-signed build may require a new authorization. The menu-bar icon stays active after the editor window closes.

## Use the editor

1. Use the **Profiles** menu to create an application or independent Manual profile, rename it, duplicate its effective layout, or import/export a profile. Global is protected from renaming and deletion.
2. Click any pad or outer button to select it; a blue outline marks the selection. Open **Actions** to assign an action, drag an action onto a control, or use **Change Action** in the inspector. The model follows the selected connected Launchpad automatically. The model picker also offers a manual preview; **Tools → Auto-Detect Model** resumes following hardware. **Tools → View Connected Device** chooses the deck displayed in the editor. Every connected supported Launchpad remains active, including multiple units of the same model.
3. Assign shortcuts, application launches, files, folders, HTTP/HTTPS websites, or Unicode text. File/folder selection stores a bookmark; choose a new location if it becomes unavailable. Click the shortcut recorder and press the shortcut to record its physical key code and modifiers.
4. Add and edit shortcut, resource, text, delay, shell/AppleScript, and installed extension steps in a macro. Reorder steps with the arrows. Navigation and nested macros are excluded; a macro retains at least one step.
5. Use **Views** to create, rename, reorder, and delete pages/folders, including nested folders. The page picker changes the editor page independently of the device's current page.
6. Choose a color in the inspector; expand **Artwork and Symbol** for SF Symbols, PNG/JPEG artwork and the icon composer. **Compose Icon** creates artwork from the current symbol, label, and color. The desktop preview shows artwork and text; physical Launchpads show RGB LED colors.
7. Open **Tools → Lighting and LED Art** to paint an 8×8 LED image, import a square-cropped PNG/JPEG, preview per-button press animations, and add page-wide breathing, rainbow, scanner, or audio-level effects. Choose whether running apps and action feedback light their assigned pads. The preview never triggers an action. Microphone input stays off until explicitly enabled, and pauses with the deck.
8. Mappings are shared across Launchpad models by default. Open **Tools → Model-Specific Layouts** to inspect dormant overrides. Enabling them shows a warning and requires unlocking before model-specific edits; returning to shared mappings keeps the saved overrides available.

The deck expands with the window instead of stopping at 54-point buttons. The native window frame, Liquid Glass button surfaces, square pad shapes and physical arrangement are preserved. The inspector can be hidden for more workspace. In smaller windows, the deck scrolls at a readable minimum control size, and inspector fields and tool panels scroll within their bounds. Long feedback opens in a details popover.

Editor layouts and device descriptors are cached; artwork loads as downsampled thumbnails off the main thread with a 32 MB cache. Pads share a `GlassEffectContainer` without merging their shapes, following [Apple’s custom Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views). Configuration saves remain immediate and atomic, using compact internal JSON; portable exports remain formatted.

Profiles use **Shared** mappings by default: grid assignments and common top/right controls stay the same when you change models. Virtual decks show the 64 grid controls; physical models also show their available outer controls. Editing through a virtual preview preserves physical outer-button assignments. Each physical device keeps its own current page/folder and held-button state while using the same active profile.

**Tools → Model-Specific Layouts** unlocks independent layouts after a warning. Previously saved model layouts become active; models without one start from the shared mapping. Pro-only left/bottom/Shift controls require this option. Turn it off to lock model settings and return to shared mappings; saved model layouts are retained. Shared editing remains available while model settings are locked. **Tools → Copy Layout…** is available with model layouts enabled, previews controls without a destination, and supports Undo. Exports and duplication preserve saved layouts even while overrides are off.

Application profiles inherit their matching Global model’s pages, folders, and assignments until they supply a control override or an explicit disabled control. **Clear Control** removes an override and restores inheritance. Manual profiles are independent. Duplicating an application profile creates an independent Manual snapshot, including its inherited controls.

### Runtime activation and navigation

The status area below the deck and menu bar show the active runtime profile, **Auto/Manual** mode, and current page/folder path. Selecting a profile in the sidebar changes the editor only. **Activate Profile** pins any selected profile until you choose **Auto: Follow Frontmost App**, including across restarts. Auto uses the frontmost app's profile or falls back to Global. Deleting the pinned profile returns to Auto.

Assign **Open Folder**, **Back**, **Home**, **Previous Page**, or **Next Page** to any control; no buttons are reserved. Back follows folder-entry history. Home returns to the initial root page. Previous/Next stop at the current folder's page boundaries. Profile changes reset runtime navigation to Home. The initial Home page and inherited views cannot be deleted from an application profile; a folder must retain a page, or be deleted as a whole.

### Execution and feedback

LaunchDeck runs one sequence at a time and stops at the first failure. An explicit launch/open step waits for the opened app to become active, then sends subsequent keyboard/text steps there. Unexpected foreground app changes cancel sequences containing keyboard/text input. Disconnecting, pausing, navigating, manually changing activation, sleeping, switching away from the user session, or quitting cancels active execution and releases keyboard modifiers.

On system sleep or user-session deactivation, LaunchDeck stops device monitoring and suspends hardware actions. It reconnects, refreshes the foreground app and permissions, and repaints the current layout when both the computer and user session are active again. This preserves the user’s Pause setting, profile activation, and navigation; cancelled macros are not resumed.

Keyboard and text steps require Accessibility access; resource opening and navigation do not. Unicode text entry leaves the clipboard unchanged. Success feedback means keyboard events were **dispatched**, since macOS cannot confirm that another app consumed them. Busy, missing resource, permission, cancellation, and execution errors appear in the editor, with brief LED feedback when applicable. While LaunchDeck's editor is frontmost, physical action presses select controls for editing; assigned navigation actions still navigate the runtime deck. The editor remains usable with no device connected.

Disabled controls show a neutral face in the editor and no LED color on hardware or the companion, regardless of a previously saved color. The labelled **Pause** switch starts **off** (running), turns **on** when paused, and controls all connected devices. Disconnects and delayed events are isolated by device identity and connection lifetime; reconnecting a unit cannot replay its old presses or LED feedback.

### Profile files and storage

Configuration is saved atomically in `~/Library/Application Support/LaunchDeck/profiles.json`; artwork is stored in its `Artwork` subdirectory. Version 1 and 2 configurations migrate to version 3 with original IDs, bindings, colors, shortcuts, macros, and app associations preserved. The original is backed up as `profiles.v1.backup.json` or `profiles.v2.backup.json` before migration. Existing Mini mappings become the shared layout; previously saved model layouts are retained behind the optional `modelOverridesEnabled` setting, which defaults to false when absent. If a configuration cannot be read, LaunchDeck displays the error and protects the original from being overwritten. Restore the file and restart; export any new in-memory work first. Save failures are shown, with edits retained in memory.

**Export Profile** writes a single `.launchdeckprofile` file containing a JSON manifest, all effective independent model layouts, and embedded artwork. **Import Profile** validates the full file and artwork, creates fresh profile/artwork IDs, and adds a Manual profile without replacing existing profiles. PNG/JPEG artwork is normalized to PNG; images must be at most 4096×4096 and 20 MB, and profile packages at most 100 MB. Referenced applications and external files must still be available on the importing computer; their contents are not embedded. Imported script IDs are renewed and require local enabling; machine-specific approvals and Keychain secrets are never exported.

## Scripts, integrations, and community content

Assign **Shell Script** or **AppleScript** in the inspector or macro editor. Use inline code or a native file picker, literal positional arguments, and a timeout. Review and enable each exact script on this Mac; changing content or arguments requires enabling that variation again. Multiple configured variations can be enabled independently. Script output is bounded and shown under **Latest script output**; failures stop the sequence. Cancellation and timeout terminate the interpreter’s process group, including background children.

File contents are captured once before permission checks and matched against local consent. Shell files run as captured UTF-8 code with the original path as `$0`. AppleScript text or compiled files run from a private temporary snapshot, so `path to me` refers to that snapshot; pass original resource paths as arguments where needed. Automation failures explain the relevant System Settings panel. Local approvals live in `script-approvals.json`, separate from portable profiles.

Open **Tools → Extensions** to install/update `.launchdeckextension` manifests, enable/disable them, manage local Keychain references, or remove them. Installed actions appear in the palette, inspector, and macro editor. Recipes support existing actions, scripts and HTTP requests; parameter values are structurally substituted, never evaluated as code. Expanded recipes use the shared permission/focus/cancellation rules. Missing or disabled extensions retain assignments and report how to repair them. Supported app/service metadata appears in the extension panel. See [extension authoring](docs/ecosystem/extension-authoring.md) and its JSON schema.

**Tools → Community Content** provides searchable profiles, icon packs and extensions, with model/app filters, installed versions and updates. Bundled starter content works offline. Supply an HTTPS catalog URL to browse remote content; downloads validate declared size, SHA-256 and package references before installation. Catalogs may use loopback HTTP during development. Profile downloads always add independent Manual profiles. Icon packs become available in the inspector’s artwork picker. Service tokens are local Keychain values, never package contents; manifests declare allowed HTTP hosts and secret reference names. The bundled Home Assistant integration provides an API check and light action that require your own URL/entity/token configuration. No service is invoked during installation.

See [catalog authoring](docs/ecosystem/catalog-authoring.md) and [working starter packages](Samples/Ecosystem/README.md). The configurable catalog is the distribution mechanism; this repository does not operate a hosted marketplace.

## Phone and tablet deck

Select **Virtual Deck** in the model preview to edit its 64 grid controls. These use shared mappings by default; enable model-specific layouts for a separate phone/tablet assignment. **Tools → Phone / Tablet** opens local companion settings with addresses, a QR code, an expiring pairing code, and per-browser revocation. Profiles, activation, navigation, colors and artwork stay synchronized with the Mac; stale presses are rejected and disconnection disables buttons. Physical devices and the companion have independent folder history and share one executor. Stopping or revoking a companion cancels its active sequence. Detailed action errors stay on the desktop; browser snapshots contain presentation values without scripts, bookmarks, URLs or service secrets.

The browser companion uses local HTTP on a trusted IPv4 network. There is no cloud account or relay. See [pairing, security and limits](docs/companion/README.md).

## Test and build

```sh
swift test
xcodebuild build \
  -project LaunchDeck.xcodeproj \
  -scheme LaunchDeck \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/LaunchDeck-DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

## Releases

GitHub Actions builds a universal, ad-hoc-signed DMG and ZIP on version tags and publishes them as a GitHub prerelease. These are **unnotarized preview builds**. macOS may require the user to approve the app in System Settings before first launch. The optional **Notarized artifact** workflow builds a signed and notarized DMG and uploads it for download; it does not publish automatically. See [distribution setup](docs/distribution/README.md).

An actual notarization ticket has not been verified in this session.

## Verification and limits

`swift test` passes 121 tests, covering protocol mappings, migration, persistence, execution, packages, catalogs, companion transport and coordinator behavior. Native arm64 and x86_64 builds are verified. Desktop UI checks cover disconnected model previews, tool panels and copy previews; responsive browser checks cover phone/tablet viewports, feedback, activation, pairing and disconnect states.

Physical Mini/X/Pro MIDI input, LEDs, reconnects and real phone/tablet Wi-Fi behavior still require device acceptance. Accessibility/Automation-controlled target-app dispatch and a signed/notarized release require the relevant local permissions and credentials. Synthetic events may be rejected by Secure Input or individual apps; dispatched feedback does not confirm target acceptance. Hardware-specific labels/artwork appear in LaunchDeck, while Launchpads use RGB LEDs. Logitech/Elgato hardware adapters, a hosted marketplace, cloud synchronization and native mobile editing are outside this delivery.

## License

Copyright © 2026 Reom Nagasaka.

LaunchDeck is licensed under GPL-3.0-only. See [LICENSE](LICENSE).
