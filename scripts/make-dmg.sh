#!/usr/bin/env bash
# Wrap the notarized .app in a Developer ID signed DMG with a drag-to-Applications layout.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if ! command -v create-dmg >/dev/null 2>&1; then
  die "create-dmg not found. Install with: brew install create-dmg"
fi

if [[ ! -d "$APP_PATH" ]]; then
  die "$APP_PATH not found. Run 'make notarize-app' first."
fi

echo "==> create-dmg"
rm -f "$DMG_PATH"

# create-dmg stages its source into a temp dir, so hand it a clean directory
# containing just the .app to avoid picking up stray files.
STAGE_DIR="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"

create-dmg \
  --volname "Bridge Commander $VERSION" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 140 190 \
  --app-drop-link 400 190 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGE_DIR"

echo "==> codesign DMG"
codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "Built $DMG_PATH"
