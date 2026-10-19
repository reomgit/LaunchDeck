#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'Usage: package-dmg.sh /path/LaunchDeck.app /path/LaunchDeck.dmg' >&2
  exit 2
fi

package_app="$1"
package_dmg="$2"
[[ -d "$package_app" && "$package_app" == *.app ]] || { echo 'App bundle not found.' >&2; exit 2; }
[[ "$package_dmg" == *.dmg ]] || { echo 'Output path must end in .dmg.' >&2; exit 2; }

package_stage="$(mktemp -d)"
trap 'rm -rf "$package_stage"' EXIT
ditto "$package_app" "$package_stage/LaunchDeck.app"
ln -s /Applications "$package_stage/Applications"
hdiutil create \
  -volname 'LaunchDeck' \
  -srcfolder "$package_stage" \
  -ov \
  -format UDZO \
  "$package_dmg"
