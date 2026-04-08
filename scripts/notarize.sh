#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/Glance.zip}"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/Glance.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile name}"

require_env_var NOTARY_PROFILE

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "error: zip archive not found at $ZIP_PATH" >&2
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Notarized and stapled $APP_BUNDLE"
