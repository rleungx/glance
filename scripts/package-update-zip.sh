#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/Glance.app}"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/Glance.zip}"
APPCAST_OUTPUT="${APPCAST_OUTPUT:-$DIST_DIR/appcast.xml}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if [[ -f "$APPCAST_OUTPUT" ]]; then
  rm -f "$APPCAST_OUTPUT"
fi

echo "Created update archive at $ZIP_PATH"
