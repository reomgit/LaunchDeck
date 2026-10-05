# LaunchDeck eventual workflow goals

Status: proposed design, awaiting user confirmation. This document keeps the original checklist and earlier future roadmap in scope; it does not redefine the goal as only the work already implemented.

## Scope and existing behavior

Extend the existing native macOS 26+ SwiftUI utility with extensions, downloadable community content, additional device layouts, a synchronized phone/tablet virtual deck, and the shell/AppleScript actions and notarized distribution discussed in the earlier MVP chat. Preserve the existing Mini MK3 assignments, application inheritance, manual activation, navigation, artwork, undo, execution cancellation, menu-bar lifecycle, and unreadable-configuration protection. Swift remains the desktop implementation language and GPL-3.0-only remains the license.

The September desktop workflow implementation is present but uncommitted. No existing edits may be discarded. Its completion evidence is separate from evidence for these additions.

## Approaches

1. **Recommended: shared desktop services with portable extensions and a browser companion.** Use manifest-defined actions, a downloadable content catalog, device adapters, and a responsive local-network virtual deck. This reaches all four requested areas without requiring an App Store release or a hosted account service. Integration actions can call documented HTTP services in addition to existing desktop actions.
2. **Native companion and executable plugin processes.** A separate iOS/iPadOS project and an isolated executable plugin protocol provide more platform capabilities, but introduce deployment/signing, process supervision, and a substantially larger SDK. This is appropriate if native mobile distribution or arbitrary plugin code is part of the intended end state.
3. **Hosted marketplace and cloud synchronization.** Accounts, publishing/moderation, and cloud profile synchronization support remote access and a public ecosystem, but need deployed services and operational ownership. No hosting/account infrastructure is currently specified in the project.

The following design uses approach 1. The browser companion, proposed device models, and declarative extension format are design choices requiring confirmation, rather than previously agreed requirements.

## Milestone 1: device and configuration foundations

Introduce `DeviceDescriptor` and a `DeviceAdapter` interface for control identity, position, label, capabilities, incoming events, programmer-mode messages, and LED encoding. Implement Mini MK3, Launchpad X, and Launchpad Pro MK3 adapters against Novation's programmer references. Match input/output endpoints from the same physical device; expose a device selector and retain the existing connection-generation protection. One selected hardware device remains active at a time, with the companion usable alongside it.

Keep the existing 0–79 Mini control indices stable. Extend the control model to cover the Pro's documented assignable perimeter controls and render actual positions from descriptors instead of fixed Mini-only rows. A profile carries independent layouts for each device model. Application profiles inherit the Global layout for the same model. Provide an explicit Copy Layout operation with a mapping preview; never silently drop assignments during conversion. Keep unsupported assignments available when editing a different model.

Migrate schema 2 to schema 3 with an untouched backup before writing. Existing content becomes the Mini MK3 layout with all IDs, assignments, page order, activation, and assets retained. Continue to read schema 1 through the existing migration path. Profile packages carry schema/model compatibility metadata and all model layouts.

## Milestone 2: extensions and integrations

First add explicitly enabled Run Shell Script and Run AppleScript actions to the palette, inspector, and macros. Use a separate native Swift process executor with cancellation, a configurable timeout, bounded stdout/stderr, exit-status reporting, and process-tree termination. Support inline scripts and persistent bookmarked script files. Imported scripts remain visible but require local enabling before execution; never execute scripts during package validation or installation. AppleScript actions declare target applications and provide per-target Automation permission guidance, with the required usage description. These actions do not require Accessibility unless subsequent steps send keyboard/text events. Preserve clipboard contents and the existing single-sequence contract.

Define a versioned `.launchdeckextension` package containing a manifest, author/version/license, supported applications/services, action IDs, parameter definitions, icons, and executable action recipes. Recipes combine resource/shortcut/text/delay steps, HTTP requests, and locally enabled shell/AppleScript steps. Parameter types include strings, choices, booleans, numbers, URLs, and secret references. Recipes cannot introduce nested macros or navigation into a running sequence. Shell arguments and script parameters remain structured rather than interpolating arbitrary values into command text.

Persist extension action references and parameter values in bindings and macro steps. Resolve them at execution time through `ExtensionRegistry`; updates retain stable IDs and detect incompatible parameter changes. Missing/disabled extensions remain editable and display a recoverable unavailable-action message. Extension keyboard/text steps use the existing permission and focus checks. HTTP actions report transport/non-success status failures, have cancellation/timeouts, and keep credentials in Keychain rather than profile exports. Packages declare service hosts; requests must match them. Secret values are entered locally after installation/import.

Provide an Extensions window for installed versions, supported apps/services, install from file/catalog, update checks, enable/disable, and removal. Validate complete packages before installing, stage updates atomically, and retain the previous installation if validation fails. Removing an extension leaves its action references intact so reinstalling repairs them.

Ship a documented SDK, schema, complete example extension, and a working integration example for a documented HTTP service. Discovery and execution must be connected to the ordinary action palette, inspector, macros, feedback, and undo flows; a manifest parser alone is insufficient.

## Milestone 3: community profiles and artwork

Add a Content Library that reads a versioned catalog from a user-configurable HTTPS URL, with a bundled starter catalog and content for disconnected use. Catalog entries contain stable IDs, type, author, license, description, supported apps/device models, version, artifact URL, size, and SHA-256 digest. Support profiles, icon packs, and extensions. Filter/search by type, model, and supported app/service.

Download with size limits and verify the digest and package compatibility before installation. Profile downloads use the existing independent import path and never overwrite profiles. Icon packs use a versioned `.launchdeckicons` manifest with validated images and fresh local asset IDs; expose the installed icons in the artwork chooser. Extension entries use the extension installer and expose newer compatible versions. Show recoverable download/validation errors and installed status.

Provide catalog and package authoring documentation plus checked-in sample artifacts. No fabricated public marketplace or unavailable download endpoint may be shown as live. The app must successfully consume a real HTTP-served test catalog, including updates, as part of acceptance.

## Milestone 4: synchronized phone/tablet deck

Serve a responsive virtual deck from the desktop app using a local-network service. Provide desktop Start/Stop, address/QR connection guidance, pairing, connected-client status, and revocation. Pairing requires a short-lived code shown in the desktop editor. Issue a separate revocable credential per paired client, restrict browser origins, bound request sizes/rates, and never expose unpaired action execution or the stored file bookmarks/secrets.

The companion displays effective labels, actions, artwork, colors, runtime profile/mode, folder/page, and execution feedback. Use desktop profile resolution, navigation, and the single action executor for remote presses; do not create a separate runtime implementation. Expose runtime profile activation and Auto controls. Synchronize subsequent desktop edits, profile changes, navigation, and artwork with a revisioned snapshot protocol. Remote presses include the displayed revision and page ID so stale controls are rejected rather than executing a different assignment.

Provide a virtual layout available without connected MIDI hardware, with independent layouts and explicit copying from hardware layouts. The desktop remains authoritative. Reconnect fetches a current snapshot; the companion shows disconnected state and disables action execution while offline. Stop/quit revokes active sessions and cancels companion-originated execution. Shared layout editing on mobile is not required by the original checklist; mobile profiles/actions remain synchronized to desktop edits.

## Verification and deliverables

Keep all 48 existing tests. Add substantive coverage for schema migration/backup, all supported control mappings, device endpoint pairing, layout isolation/inheritance/conversion, and model-aware LEDs/navigation. Add script timeout/output/exit/cancellation/child-process tests, imported-script enabling, and injected Automation permission tests. Add extension serialization, recipe expansion, parameter/host validation, unavailable references, atomic installation/update failure, cancellation, per-step permissions, and credential exclusion tests.

Test catalog download/digests, profile/icon/extension package round trips, malformed content, update discovery, rollback, and preservation of existing profiles. Test companion pairing expiry/revocation, unauthenticated rejection, snapshot synchronization, stale presses, shared executor/navigation, disconnect/stop, and multiple paired clients using injected transport dependencies and real loopback integration tests.

Run `swift test`, plist validation, `git diff --check`, and native arm64/x86_64 builds. Exercise all new editor flows and the responsive companion in a browser. Physically verify each supported hardware model and a phone/tablet connection when those devices are available; record missing hardware verification explicitly rather than treating protocol tests as physical proof.

Update README, extension/catalog authoring documentation, sample content, and `.agent/CONTINUITY.md`. Completion requires functioning user flows for the full scope, not just infrastructure or green tests. A public hosted marketplace is an alternative architecture rather than a prerequisite for consuming downloadable community catalogs.

## Milestone 5: Developer ID distribution

Extend the existing GitHub release workflow with an optional Developer ID path: import credentials into a temporary keychain, sign the universal app with hardened runtime and appropriate entitlements, verify the signature, submit for notarization, staple and validate the ticket, then package and checksum the distributable with corresponding source/license. Keep the working ad-hoc preview path when Developer ID credentials are not configured. Document required GitHub secret names and local verification commands without exposing values.

Actual notarized-release acceptance requires the user's Apple Developer membership, certificate, notarization credentials, and authorization to submit/publish. Implement and verify the pipeline locally as far as available credentials permit; a configured workflow alone is not evidence of a notarized release. Record this external dependency as outstanding until a signed/notarized artifact is verified.

## Primary protocol sources

- Launchpad X surface and LED protocol: https://userguides.novationmusic.com/hc/en-gb/articles/24001475492498-Controlling-the-Launchpad-X-surface (updated 2025-01-21; inspected 2026-10-06).
- Launchpad Pro MK3 programmer reference: https://fael-downloads-prod.focusrite.com/customer/prod/s3fs-public/downloads/LPP3_prog_ref_guide_200415.pdf (inspected 2026-10-06).

## Approval

Confirm the full scope and recommended approach, or specify a change to the extension format, device models, or companion platform before implementation. No implementation of these new subsystems has started.
