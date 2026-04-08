#!/bin/zsh
set -euo pipefail

if [[ -n "${GLANCE_RELEASE_ENV_LOADED:-}" ]]; then
  return 0
fi
export GLANCE_RELEASE_ENV_LOADED=1

ROOT_DIR="$(cd "$(dirname "${(%):-%N}")/../.." && pwd)"
DEFAULT_RELEASE_ENV_FILE="$ROOT_DIR/Packaging/macOS/release.env"
RELEASE_ENV_FILE="${RELEASE_ENV_FILE:-$DEFAULT_RELEASE_ENV_FILE}"

load_release_env() {
  if [[ -f "$RELEASE_ENV_FILE" ]]; then
    set -a
    source "$RELEASE_ENV_FILE"
    set +a
  fi
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_env_var() {
  local name="$1"
  local value="${(P)name:-}"
  [[ -n "$value" ]] || die "$name is required"
}

require_https_url_var() {
  local name="$1"
  require_env_var "$name"
  local value="${(P)name}"
  [[ "$value" == https://* ]] || die "$name must use an https URL"
}

require_existing_file_var() {
  local name="$1"
  require_env_var "$name"
  local value="${(P)name}"
  [[ -f "$value" ]] || die "$name must point to an existing file"
}

require_existing_directory_var() {
  local name="$1"
  require_env_var "$name"
  local value="${(P)name}"
  [[ -d "$value" ]] || die "$name must point to an existing directory"
}

assert_non_placeholder_value() {
  local name="$1"
  local forbidden_value="$2"
  local value="${(P)name:-}"
  [[ "$value" != "$forbidden_value" ]] || die "$name still contains a placeholder value"
}

load_release_env
