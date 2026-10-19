#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
# No credentials are echoed. Store notarization credentials with notarytool first.
if [[ $# -ne 3 ]]; then
  echo 'Usage: notarize-release.sh /path/LaunchDeck.app signing-identity keychain-profile' >&2
  exit 2
fi
release_app="$1"
release_identity="$2"
notary_profile="$3"
[[ -d "$release_app" && "$release_app" == *.app ]] || { echo 'App bundle not found.' >&2; exit 2; }
[[ "$release_identity" != '-' && -n "$notary_profile" ]] || { echo 'Developer ID and notarization profile required.' >&2; exit 2; }
release_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="$(mktemp -d)"
trap 'rm -rf "$release_dir"' EXIT
codesign --force --options runtime --timestamp --sign "$release_identity" \
  --entitlements "$release_root/LaunchDeck/Distribution.entitlements" "$release_app"
codesign --verify --strict --verbose=2 "$release_app"
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_dir/submission.zip"
notary_arguments=(--keychain-profile "$notary_profile" --wait --output-format json)
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then notary_arguments+=(--keychain "$NOTARY_KEYCHAIN"); fi
xcrun notarytool submit "$release_dir/submission.zip" "${notary_arguments[@]}" > "$release_dir/result.json"
/usr/bin/plutil -extract status raw "$release_dir/result.json" | /usr/bin/grep -qx Accepted || { echo 'Notarization was not accepted. Inspect notarytool history/log.' >&2; exit 1; }
xcrun stapler staple "$release_app"
xcrun stapler validate "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
echo 'Signed, notarized, stapled, and assessed successfully.'
