#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/Glance.app}"
IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"
ENTITLEMENTS_FILE="${ENTITLEMENTS_FILE:-}"

require_env_var CODESIGN_IDENTITY

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

if [[ -n "$ENTITLEMENTS_FILE" ]]; then
  [[ -f "$ENTITLEMENTS_FILE" ]] || die "ENTITLEMENTS_FILE must point to an existing file"
fi

frameworks_dir="$APP_BUNDLE/Contents/Frameworks"
if [[ -d "$frameworks_dir" ]]; then
  for framework in "$frameworks_dir"/*.framework; do
    [[ -e "$framework" ]] || continue
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$framework"
  done
fi

codesign_args=(--force --options runtime --timestamp --sign "$IDENTITY")
if [[ -n "$ENTITLEMENTS_FILE" ]]; then
  codesign_args+=(--entitlements "$ENTITLEMENTS_FILE")
fi

codesign "${codesign_args[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Codesigned $APP_BUNDLE"
