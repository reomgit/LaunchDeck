# Editor usability and performance pass

User delegated decisions; improve the small deck, clipped UI and perceived weight without losing existing workflows or changing hardware layout.

- Root: compact workspace, prominent adaptive deck, grouped native Liquid Glass rendering, asynchronous bounded artwork thumbnails, screen-aware native windows, Tools/palette organization.
- Performance worker: immutable device descriptors and editor resolution caches; preserve disabled bindings, inheritance, observation, undo and immediate save behavior.
- Responsive panels worker: bounded inspector editors, adaptive extension/community/companion panels and cached QR rendering.
- Read-only audits: clipping and reproducible isolated release benchmarks.

Acceptance: all physical controls and every action remain reachable; deck uses available space with no 54-point cap; small windows scroll the deck rather than producing unreadable cells; long inputs and panels stay within their bounds; no image disk decode in view bodies; native glass grouped without merging buttons; cache invalidation tested; core tests and both architecture builds pass; native UI checked at default and smaller sizes across models.

Baseline: 105 displayed/inherited lookups 51.893 ms (one populated page), 617.316 ms (12 pages); equivalent single merge/dictionaries 0.308/3.380 ms. 105 warm artwork file loads/decode 19.441 ms vs cached 0.293 ms. Actual label edit/save/refresh 7.679/90.001 ms. Isolated benchmark source, script and results in /tmp/LaunchDeck-performance-audit-baseline.

Keep existing dirty edits; no blanket commit/reset. Native macOS verification is required because SwiftUI/AppKit are unavailable in Linux containers. No system dependencies installed.

## Implemented and verified

User clarified that native Apple Liquid Glass, window frames and Launchpad buttons must be preserved. Final implementation retains native window chrome, tinted glass faces, original square/control corner radii, 7-point physical gaps and the Novation mark. A zero-spacing GlassEffectContainer batches the effects while keeping every button distinct; fixed square bounds and size-aware label/icon content prevent small controls from stretching into adjacent rows.

- Compact workspace: Actions popover (drag or click selected control), model/page/Tools row, hideable 300-point inspector, runtime/status footer, bounded feedback details.
- Initial native frame fits the screen; supported content minimum 920×580 rather than the previous forced 1280×860 minimum. Default preferred content size retained. Deck expands to available space (44–96 point cells), with scrolling at smaller sizes.
- Cached editor snapshots retain raw disabled bindings, preindex bindings/local overrides and invalidate with configuration. Observed inputs are read on cache hits; regression tests cover undo, Global edits, page/model/profile changes.
- Immutable descriptors; one-pass inherited binding merge; compact immediate atomic configuration saves. Async downsampled artwork with 256-entry/32 MB cache and coalesced requests; QR context/image reuse.
- Bounded text/script editors and adaptive scrollable community/extension/companion panels. No empty artwork grid pushing the action editor below the viewport.

Release CPU benchmark on same fixtures: 105 warm editor lookups 51.893→0.229 ms (1 page), 617.316→0.132 ms (12 pages); label edit/save/runtime refresh 7.679→4.061 and 90.001→39.920 ms. Large-fixture validation 25.740→3.132 ms; companion snapshot 1.528→0.209 ms; 105-color MIDI frame 0.249→0.032 ms. These timings measure CPU work, not GPU frame rate or cold file access. Logs: /tmp/LaunchDeck-ui-benchmark-final.log; reproducible baseline runner/snapshot /tmp/LaunchDeck-performance-audit-baseline.

121 tests pass (25 XCTest + 96 Swift Testing); original 10 core tests retained. Final arm64 and x86_64 native builds pass; plist lint and diff whitespace checks pass. Xcode only emits its pre-existing skipped AppIntents extraction warning. Logs /tmp/LaunchDeck-ui-{tests,arm64,x86_64}.log.

Native CUA checks: populated artwork and long profile names at default size; bounded 80-line Unicode editor; 1040×680 content fixture with distinct square Pro buttons and bottom-row scrolling; full X and virtual layouts after switching; Actions popover and community sheet with all controls reachable. Isolated fixture/project /tmp/LaunchDeck-ui-native; test data does not replace user profiles. No physical-device acceptance or GPU/FPS benchmark claimed. Implementation assistants encountered a usage limit after partial work; root completed and reviewed their edits.

Fixed an unrelated flaky selected-port test: 49383 was occupied by an outgoing process connection, even though no listener existed. Test now obtains an unused TCP port across interfaces and still verifies exact selected-port binding. Companion implementation unchanged.

Workspace executable rebuilt in build/DerivedData; old duplicate dev processes closed and new build reopened. Final native screenshot confirms all80 Mini controls, larger separate glass squares, native window chrome and retained user profiles. Isolated previews closed. Accessibility is reported as required by the rebuilt binary; no permission changes performed.
