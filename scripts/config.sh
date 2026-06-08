#!/usr/bin/env bash
# Shared configuration for release scripts. Source this from every script.
# Exits non-zero if required env vars are missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="$PROJECT_ROOT/.env.release"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

die() {
  echo "error: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    die "$name is not set. Define it in $ENV_FILE or export it in your shell."
  fi
}

require_env DEVELOPER_ID_APPLICATION
require_env APPLE_TEAM_ID
require_env NOTARY_PROFILE

APP_NAME="Bridge Commander"
SCHEME="BridgeCommander"
BUNDLE_ID="com.bridgecommander.BridgeCommander"
XCODEPROJ="$PROJECT_ROOT/BridgeCommander.xcodeproj"

BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/BridgeCommander.xcarchive"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/BridgeCommander.zip"

parse_version() {
  # MARKETING_VERSION is defined per-configuration in the committed pbxproj;
  # the Debug and Release values match, so the first match is authoritative.
  grep -m1 'MARKETING_VERSION = ' "$XCODEPROJ/project.pbxproj" \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' \
    | tr -d ' "'
}

VERSION="$(parse_version)"
if [[ -z "$VERSION" ]]; then
  die "Could not parse MARKETING_VERSION from $XCODEPROJ/project.pbxproj"
fi

DMG_PATH="$DIST_DIR/BridgeCommander-$VERSION.dmg"

mkdir -p "$BUILD_DIR" "$DIST_DIR"

export SCRIPT_DIR PROJECT_ROOT APP_NAME SCHEME BUNDLE_ID XCODEPROJ \
       BUILD_DIR DIST_DIR ARCHIVE_PATH APP_PATH ZIP_PATH VERSION DMG_PATH
