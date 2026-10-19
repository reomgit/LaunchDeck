# Developer ID distribution

Ad-hoc universal previews remain available through the existing version-tag CI. The optional **Notarized artifact** workflow is dispatched explicitly against a branch, tag or commit; it does not create a GitHub release or publish automatically.

Configure a GitHub `distribution` environment with these secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12` certificate, including its private key.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: `.p12` password.
- `DEVELOPER_ID_APPLICATION_IDENTITY`: exact Developer ID Application signing identity.
- `NOTARY_APPLE_ID`, `NOTARY_APP_PASSWORD`, `NOTARY_TEAM_ID`: Apple Developer account, app-specific password and team.

The job runs tests, builds a universal Release archive, imports credentials into a temporary keychain, signs with hardened runtime and the Apple Events entitlement, submits through `notarytool`, verifies Accepted status, staples the ticket, and runs Gatekeeper assessment. It uploads the app ZIP/checksum plus the exact checked-out source archive and GPL license. Failure at any verification step stops artifact upload. The temporary signing keychain and certificate file are removed on exit. No tracing or secret echo is enabled.

For local packaging, store credentials first using `xcrun notarytool store-credentials` and run:

```sh
scripts/notarize-release.sh /path/to/LaunchDeck.app 'Developer ID Application: Your Identity' your-keychain-profile
```

Set `NOTARY_KEYCHAIN` if the profile lives in a custom keychain. The script modifies the supplied app bundle, so use an archive copy. Compile Release with signing disabled before this step; debug `get-task-allow` entitlements must not be retained. LaunchDeck uses no embedded third-party executables; its native shell/AppleScript actions use system interpreters. `Distribution.entitlements` enables Apple Events for explicitly enabled scripting; keyboard access still requires macOS Accessibility permission.

Validation here covers Bash syntax, plist structure, workflow arguments against local `notarytool --help`, and unsigned arm64/x86_64 builds. An accepted notarization ticket and signed runtime behavior remain unverified until Developer ID credentials are configured and a distribution job runs.

References: [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [hardened runtime](https://help.apple.com/xcode/mac/current/en.lproj/devf87a2ac8f.html).
