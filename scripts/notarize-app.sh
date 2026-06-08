#!/usr/bin/env bash
# Submit the signed .app to Apple's notary service and staple the ticket.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if [[ ! -d "$APP_PATH" ]]; then
  die "$APP_PATH not found. Run 'make build-release' first."
fi

echo "==> ditto zip $APP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> notarytool submit (waiting)"
set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$ZIP_PATH" \
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
  die "App notarization failed."
fi

echo "==> stapler staple $APP_PATH"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "Notarized and stapled $APP_PATH"
