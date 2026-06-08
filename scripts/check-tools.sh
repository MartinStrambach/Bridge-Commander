#!/usr/bin/env bash
# Verify all tools and credentials required for a release build are in place.
# Prints actionable fix-it instructions for anything missing.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

ok=1
check() {
  local label="$1" fix="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  ok   $label"
  else
    echo "  miss $label"
    echo "       fix: $fix"
    ok=0
  fi
}

echo "Checking release tools..."
check "create-dmg on PATH" \
      "brew install create-dmg" \
      command -v create-dmg
check "xcrun notarytool available" \
      "install Xcode command-line tools: xcode-select --install" \
      xcrun --find notarytool
check "xcrun stapler available" \
      "install Xcode command-line tools: xcode-select --install" \
      xcrun --find stapler

echo "Checking signing identity..."
if security find-identity -p codesigning -v 2>/dev/null | grep -Fq "$DEVELOPER_ID_APPLICATION"; then
  echo "  ok   Developer ID certificate in keychain"
else
  echo "  miss Developer ID certificate '$DEVELOPER_ID_APPLICATION' not found in login keychain"
  echo "       fix: install the Developer ID Application certificate from developer.apple.com"
  ok=0
fi

echo "Checking notarytool keychain profile..."
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "  ok   keychain profile '$NOTARY_PROFILE' works"
else
  echo "  miss keychain profile '$NOTARY_PROFILE' missing or invalid"
  echo "       fix: xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "              --apple-id <your-apple-id> --team-id $APPLE_TEAM_ID"
  ok=0
fi

if [[ $ok -eq 1 ]]; then
  echo "All release prerequisites satisfied. Version $VERSION."
else
  exit 1
fi
