# LaunchDeck

LaunchDeck turns a Novation Launchpad Mini MK3 into an app-aware macOS shortcut controller.

It is a native SwiftUI menu-bar utility for macOS 26 or later. The first release supports one Launchpad Mini MK3 through its `MIDI In/Out` interface, keyboard shortcuts, ordered shortcut-and-delay macros, Global presets, and per-application overrides.

## Requirements

- macOS 26.0 or later
- Xcode 27 or later
- Novation Launchpad Mini MK3 connected by USB
- Accessibility permission, which lets LaunchDeck post keyboard events to the foreground app

LaunchDeck uses the device's Programmer mode while connected and restores Live mode when it quits. It does not require screen-recording or Apple Events permission.

## Run from source

```sh
git clone https://github.com/reomgit/LaunchDeck.git
cd LaunchDeck
open LaunchDeck.xcodeproj
```

Choose the `LaunchDeck` scheme and run it. Grant Accessibility access when LaunchDeck asks. The menu-bar icon stays active after the editor window closes.

## Use the editor

1. Pick the Global preset or create an application preset from the sidebar.
2. Drag a Shortcut or Macro tile onto a grid cell, or select a cell and edit it in the inspector.
3. Click the shortcut recorder and press the shortcut to record its physical key code and modifiers.
4. Add shortcut and delay steps to a macro. LaunchDeck runs one macro at a time and cancels it if the foreground app changes.

An application preset inherits Global assignments until it supplies a pad assignment or an explicit disabled pad.

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

GitHub Actions builds a universal, ad-hoc-signed ZIP on version tags. These are **unnotarized preview builds**. macOS may require the user to approve the app in System Settings before first launch.

Developer ID signing and notarization are intentionally deferred. They require Apple Developer Program membership.

## Limitations

- Hardware validation requires a physical Mini MK3; CI can test only the protocol encoding and application logic.
- Secure input and some apps may reject synthetic keyboard events.
- The MVP does not run shell scripts, AppleScript, or arbitrary executable actions.
- The MVP supports a single Launchpad Mini MK3. Other Launchpad variants require a device adapter.

## License

Copyright © 2026 Reom Nagasaka.

LaunchDeck is licensed under GPL-3.0-only. See [LICENSE](LICENSE).
