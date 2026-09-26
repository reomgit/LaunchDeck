# LaunchDeck continuity

## [PLANS]

- 2026-09-26T14:38Z [USER] Implement the native Launchpad Mini MK3 MVP plan in this workspace.

## [DECISIONS]

- 2026-09-26T14:38Z [USER] Target macOS 26+, Swift-only implementation, Launchpad Mini MK3, GPL-3.0-only, shortcut-and-delay macros, and GitHub preview releases without paid signing.

## [PROGRESS]

- 2026-09-26T14:46Z [CODE] Implemented SwiftUI editor, CoreMIDI Mini MK3 adapter, app-aware resolver, Accessibility-gated keyboard executor, JSON persistence, menu-bar lifecycle, core tests, and GitHub Actions workflow.
- 2026-09-26T14:46Z [TOOL] `swift test` passed 9 core tests; arm64 and x86_64 Xcode builds succeeded. A universal archive was ad-hoc signed, verified, zipped, and checksummed.
- 2026-09-26T14:49Z [CODE] MIDI callbacks now retain a synchronized connection generation, and hot-plug removal clears held pads and cancels an active macro before reconnecting.

## [DISCOVERIES]

- 2026-09-26T14:38Z [TOOL] The project uses Xcode file-system synchronized groups, so new Swift files are automatically included in the app target.
- 2026-09-26T14:51Z [TOOL] GitHub's Xcode 26.6 runner rejects Xcode project object version 110; object version 77 is compatible with this project structure.
- 2026-09-26T15:00Z [USER+TOOL] A CoreMIDI callback triggered a Swift MainActor queue assertion. Crash-report evidence showed the callback captured `MIDIService`; it now uses a nonisolated receiver and an `AsyncStream` boundary. Added the exported drag payload UTI to the app Info.plist.

## [OUTCOMES]

- 2026-09-26T14:51Z [TOOL] Published the implementation at https://github.com/reomgit/LaunchDeck on `main` (commit `4a6bb1d`).
