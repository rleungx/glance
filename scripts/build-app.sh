#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
APP_NAME="Glance"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
INFO_TEMPLATE="$ROOT_DIR/Packaging/macOS/Info.plist"
swift build -c "$BUILD_CONFIGURATION"
BIN_PATH="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/GlanceApp"
BUILD_PRODUCTS_DIR="$BIN_PATH"
RESOURCE_BUNDLE_PATH="$BUILD_PRODUCTS_DIR/Glance_GlanceApp.bundle"
SPARKLE_FRAMEWORK_PATH="$BUILD_PRODUCTS_DIR/Sparkle.framework"
PLISTBUDDY="/usr/libexec/PlistBuddy"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.rleungx.Glance}"
APPCAST_URL="${APPCAST_URL:-https://example.com/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-REPLACE_WITH_SPARKLE_PUBLIC_KEY}"

require_env_var VERSION
require_env_var BUILD_NUMBER
require_env_var BUNDLE_IDENTIFIER
require_https_url_var APPCAST_URL
assert_non_placeholder_value SPARKLE_PUBLIC_ED_KEY REPLACE_WITH_SPARKLE_PUBLIC_KEY

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "error: built executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
  ditto "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE_PATH")"
fi

if [[ ! -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  echo "error: Sparkle.framework not found at $SPARKLE_FRAMEWORK_PATH" >&2
  exit 1
fi

ditto "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"

cp "$INFO_TEMPLATE" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleExecutable $APP_NAME" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :SUFeedURL $APPCAST_URL" "$CONTENTS_DIR/Info.plist"
"$PLISTBUDDY" -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY" "$CONTENTS_DIR/Info.plist"

echo "Built app bundle at $APP_BUNDLE"
