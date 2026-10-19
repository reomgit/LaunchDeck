# LED artwork importer implementation

Task 2 completed in the assigned source and test files only. Parent owns file picker, UI, model integration and final shared verification.

- API: `LEDGridArtwork.colors(from: Data) throws -> [PadColor]`.
- PNG/JPEG only, exactly one image, maximum 20_000_000 bytes and 4096 pixels on each source dimension.
- ImageIO metadata validates dimensions before bounded (256-pixel) thumbnail decode. ImageIO applies all EXIF rotations/reflections before a centered square fill crop.
- Render to an 8×8 sRGB bitmap, flatten transparency onto black, round channels to 0...127. Top-left maps to56; bottom-left maps to0.
- Localized import errors are ready for the parent UI.

## Evidence

Initial focused shared build encountered concurrently incomplete Lighting interfaces. Isolated SwiftPM harness `/tmp/LaunchDeckLEDArtHarness` symlinks the actual importer and tests and uses the unchanged PadColor definition extracted from Models.swift.

- RED: five accepted-image tests failed against a throwing API stub. `/tmp/LaunchDeck-led-art-red.log`.
- GREEN: eight tests pass; literal RGBA quadrants, all eight EXIF orientations, JPEG rotation, half/zero alpha, centered non-square crop, invalid/truncated data, byte cap, dimensions (both axes, exact4096 accepted), unsupported TIFF/GIF and multiframe PNG. `/tmp/LaunchDeck-led-art-tests.log`.
- Decimal byte-cap correction had its own RED:20_000_001 bytes produced invalidImage instead of dataTooLarge before changing the limit. `/tmp/LaunchDeck-led-art-cap-red.log`.
- `git diff --check -- LaunchDeck/Services/LEDGridArtwork.swift Tests/LaunchDeckCoreTests/LEDGridArtworkTests.swift` passed.

Shared focused retry was blocked by in-progress AudioReactiveMonitor interfaces (`/tmp/LaunchDeck-led-art-shared.log`). Bare `swift test` was also attempted and blocked by in-progress LightingPress/composer/LEDRenderer interfaces (`/tmp/LaunchDeck-led-art-full.log`). No importer diagnostic was present. Parent must run the complete shared suite after workers finish.

No user images were changed, no hardware used, no CUA actions, and no action/binding/model files modified. Full application/UI and physical-device acceptance remain outside this task.
