#!/bin/zsh
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/lib/release-env.sh"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
ARTIFACT_PATH="${ARTIFACT_PATH:-$DIST_DIR/Glance.zip}"
APPCAST_OUTPUT="${APPCAST_OUTPUT:-$DIST_DIR/appcast.xml}"
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:?Set DOWNLOAD_BASE_URL to the HTTPS directory hosting your Sparkle artifacts}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:?Set SPARKLE_PRIVATE_KEY_FILE to your Sparkle private key file path}"

require_https_url_var DOWNLOAD_BASE_URL
require_existing_file_var SPARKLE_PRIVATE_KEY_FILE

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "error: update artifact not found at $ARTIFACT_PATH" >&2
  exit 1
fi

tool_candidates=(
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
  "$ROOT_DIR/.build/checkouts/Sparkle/bin/generate_appcast"
)

generate_appcast=""
for candidate in "$tool_candidates[@]"; do
  if [[ -x "$candidate" ]]; then
    generate_appcast="$candidate"
    break
  fi
done

if [[ -z "$generate_appcast" ]]; then
  echo "error: could not locate Sparkle generate_appcast tool" >&2
  exit 1
fi

mkdir -p "$(dirname "$APPCAST_OUTPUT")"
"$generate_appcast" \
  --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "${DOWNLOAD_BASE_URL%/}/" \
  -o "$APPCAST_OUTPUT" \
  "$(dirname "$ARTIFACT_PATH")"

echo "Generated appcast at $APPCAST_OUTPUT"
