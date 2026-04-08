#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="${APP_BUNDLE:-$DIST_DIR/Glance.app}"
ZIP_PATH="${ZIP_PATH:-$DIST_DIR/Glance.zip}"
APPCAST_PATH="${APPCAST_PATH:-$DIST_DIR/appcast.xml}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/Glance"
FRAMEWORK_PATH="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

if [[ -f "$APPCAST_PATH" ]]; then
  require_https_url_var DOWNLOAD_BASE_URL
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

for required_key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion SUFeedURL SUPublicEDKey; do
  value="$($PLISTBUDDY -c "Print :$required_key" "$INFO_PLIST" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    echo "error: missing required Info.plist key $required_key" >&2
    exit 1
  fi
done

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "error: app executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$FRAMEWORK_PATH" ]]; then
  echo "error: Sparkle.framework not found in app bundle" >&2
  exit 1
fi

feed_url="$($PLISTBUDDY -c "Print :SUFeedURL" "$INFO_PLIST")"
public_key="$($PLISTBUDDY -c "Print :SUPublicEDKey" "$INFO_PLIST")"

if [[ "$feed_url" == "https://example.com/appcast.xml" ]]; then
  echo "error: SUFeedURL still contains placeholder value" >&2
  exit 1
fi

if [[ "$feed_url" != https://* ]]; then
  echo "error: SUFeedURL must use https" >&2
  exit 1
fi

if [[ "$public_key" == "REPLACE_WITH_SPARKLE_PUBLIC_KEY" ]]; then
  echo "error: SUPublicEDKey still contains placeholder value" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_BUNDLE"
spctl --assess --type exec -vv "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

if [[ -f "$ZIP_PATH" ]]; then
  ditto -x -k "$ZIP_PATH" "$DIST_DIR/verify-unzip"
  rm -rf "$DIST_DIR/verify-unzip"
fi

if [[ -f "$APPCAST_PATH" ]]; then
  grep -q "<rss" "$APPCAST_PATH"
fi

echo "Release verification checks passed"
