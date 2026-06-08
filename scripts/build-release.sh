#!/usr/bin/env bash
# Archive + export a Developer ID signed .app.
# Overrides the project's default ad-hoc/automatic signing at build time so we
# don't have to edit the checked-in project config.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

echo "==> xcodebuild archive"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  archive

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST

echo "==> xcodebuild -exportArchive"
EXPORT_TMP="$BUILD_DIR/export"
rm -rf "$EXPORT_TMP" "$APP_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_TMP"

EXPORTED_APP="$(find "$EXPORT_TMP" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$EXPORTED_APP" || ! -d "$EXPORTED_APP" ]]; then
  die "exportArchive did not produce a .app bundle in $EXPORT_TMP"
fi

mkdir -p "$DIST_DIR"
rm -rf "$APP_PATH"
# Exported bundle is named BridgeCommander.app (PRODUCT_NAME = TARGET_NAME);
# stage it under the display name "Bridge Commander.app".
mv "$EXPORTED_APP" "$APP_PATH"

echo "==> codesign --verify"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> spctl --assess (pre-notarization; warnings here are expected)"
spctl --assess --type execute -vv "$APP_PATH" || true

echo "Built $APP_PATH (version $VERSION)"
