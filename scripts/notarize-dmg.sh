#!/usr/bin/env bash
# Notarize and staple the DMG, then run a final Gatekeeper assessment.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if [[ ! -f "$DMG_PATH" ]]; then
  die "$DMG_PATH not found. Run 'make dmg' first."
fi

echo "==> notarytool submit $DMG_PATH (waiting)"
set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait 2>&1)"
SUBMIT_STATUS=$?
set -e
echo "$SUBMIT_OUTPUT"

SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^  id:/ {print $2; exit}')"

if [[ $SUBMIT_STATUS -ne 0 ]] || ! printf '%s\n' "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "==> notarytool log $SUBMISSION_ID"
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  fi
  die "DMG notarization failed."
fi

echo "==> stapler staple $DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> spctl --assess"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" || true

echo "Release ready: $DMG_PATH"
