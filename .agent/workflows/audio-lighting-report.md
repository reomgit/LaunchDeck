# Optional loudness input implementation

Owned files: `LaunchDeck/Core/AudioLevel.swift`, `LaunchDeck/Services/AudioReactiveMonitor.swift`, `Tests/LaunchDeckCoreTests/AudioReactiveTests.swift`.

`@MainActor @Observable AudioReactiveMonitor` has private-set `isEnabled`, `isCapturing`, `level: Double`, `statusMessage: String`, `onLevel: ((Double) -> Void)?`, `enable() async`, `disable()`, and `setSuspended(_:)`. Initial state is disabled. Only explicit `enable` may request OS permission. No configuration is read or persisted by this service. Resume checks existing permission and never prompts.

Injected `Dependencies` replaces authorization lookup/request, capture start/stop, and engine health. Tests use these replacements exclusively; they never initialize AVAudioEngine, request permission, or open a microphone. Production engine creation is deferred until explicitly enabled and authorized.

Production input preflights finite positive sample rate, nonzero channels and Float32 format before installing a nil-format input tap. RMS and dBFS normalization are the only analysis. The nonisolated tap factory never accesses MainActor, retains no PCM beyond the callback, and passes only a scalar loudness value through a nonisolated callback factory to MainActor. Every capture generation is checked after that hop; late pre-pause/pre-disable callbacks cannot repaint a resumed session. Suspension, disable, deinitialization, revoked permission, stopped engines, and startup failure release capture resources and clear loudness. A capture-only 1-second health task catches revocation/input loss even if no samples arrive; no disabled idle task remains.

Verification:

- 13 actual audio tests passed in a temporary isolated Swift package containing copies of the production files and test file: `/tmp/LaunchDeck-audio-isolated-tests.log`.
- Tests cover literal synthetic PCM RMS values and finite/range handling, opt-in/no implicit permission, explicit permission request/idempotency, pause/resume, stale generations, pending-permission cancellation, denied/revoked authorization, input failure, background delivery, and deinitialization.
- Mutation check: removing only the generation guard in the temporary package caused `pauseStopsCaptureAndResumeUsesExistingPermission` to fail (observed old level 0.8, expected 0): `/tmp/LaunchDeck-audio-mutation-tests.log`. Original production sources were unchanged by the mutation.
- Initial red diagnostics recorded absent AudioLevel/AudioReactiveMonitor before implementation. Concurrent repository compile changes prevented a clean repository-only red run.
- Repository focused `swift test --filter AudioReactiveTests` attempted; current log `/tmp/LaunchDeck-audio-lighting-tests.log` stops on in-progress AppCoordinator helpers `refreshLightingPreview`, `refreshApplicationLighting`, `updateCompanionLighting` (no audio diagnostics).
- Complete repository `swift test` attempted; current log `/tmp/LaunchDeck-audio-full-tests.log` stops on the same in-progress AppCoordinator helpers. Parent must rerun once integration lands; no whole-repository green claim is made here.
- Owned-file whitespace check passed.

Parent owns usage-description/entitlement, UI opt-in, and coordinator pause/sleep/shutdown calls. Actual microphone-device behavior and OS prompt acceptance remain untested by design.

Primary references consulted: [authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media), [installTap](https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)), [Float32 channel data/stride](https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer/floatchanneldata).
