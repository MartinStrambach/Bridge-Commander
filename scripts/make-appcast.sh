#!/usr/bin/env bash
# Write dist/appcast.xml, the Sparkle feed announcing the DMG about to be published.
#
#   make-appcast.sh <release-notes.md>   sign the DMG and write the feed
#   make-appcast.sh --check              only verify that signing will work
#
# The feed lists this release only. The app reads it from the newest GitHub release, so each
# release replaces the previous feed, and a draft release is not offered until it is published.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$APP_INFO_PLIST" 2>/dev/null
}

check_signing() {
  [[ -x "$SPARKLE_BIN/sign_update" ]] \
    || die "sign_update not found in $SPARKLE_BIN. Run 'make release'; it resolves Sparkle there."
  [[ -f "$APP_INFO_PLIST" ]] || die "$APP_PATH not found. Run 'make release' first."

  # Installed copies accept an update only if it is signed with the private half of the key
  # they were built with, so a feed signed with any other key would strand every user.
  local expected actual
  expected="$(plist_value SUPublicEDKey)" || die "$APP_PATH has no SUPublicEDKey in its Info.plist."
  actual="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" \
    || die "no Sparkle signing key in the login keychain. Import a backup with: \"$SPARKLE_BIN/generate_keys\" -f <exported-key-file>"
  [[ "$expected" == "$actual" ]] \
    || die "the keychain's Sparkle key ($actual) is not the one the app trusts ($expected)."

  FEED_URL="$(plist_value SUFeedURL)" || die "$APP_PATH has no SUFeedURL in its Info.plist."
  [[ "$FEED_URL" =~ ^(https://github\.com/[^/]+/[^/]+)/releases/latest/download/appcast\.xml$ ]] \
    || die "SUFeedURL ($FEED_URL) is not a GitHub latest-release asset URL."
  REPO_URL="${BASH_REMATCH[1]}"
}

if [[ "${1:-}" == "--check" ]]; then
  check_signing
  echo "Sparkle signing ready for $VERSION."
  exit 0
fi

NOTES_FILE="${1:-}"
[[ -f "$NOTES_FILE" ]] || die "usage: make-appcast.sh <release-notes-file> | --check"
[[ -f "$DMG_PATH" ]] || die "$DMG_PATH not found. Run 'make release' first."

check_signing

# Sparkle compares sparkle:version against the installed app's CFBundleVersion.
BUNDLE_VERSION="$(plist_value CFBundleVersion)"
MINIMUM_SYSTEM="$(plist_value LSMinimumSystemVersion)"
DMG_NAME="$(basename "$DMG_PATH")"

echo "==> sign_update $DMG_NAME"
# Prints the enclosure attributes: sparkle:edSignature="…" length="…"
SIGNATURE_ATTRIBUTES="$("$SPARKLE_BIN/sign_update" "$DMG_PATH")"

PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
# The notes go in a CDATA section, which the sequence "]]>" would end early.
NOTES="$(sed 's/]]>/]]]]><![CDATA[>/g' "$NOTES_FILE")"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <link>$REPO_URL</link>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUNDLE_VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM_SYSTEM</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO_URL/releases/tag/$VERSION</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[
$NOTES
]]></description>
      <enclosure url="$REPO_URL/releases/download/$VERSION/$DMG_NAME" type="application/octet-stream" $SIGNATURE_ATTRIBUTES />
    </item>
  </channel>
</rss>
XML

xmllint --noout "$APPCAST_PATH" || die "generated $APPCAST_PATH is not well-formed XML."

echo "Wrote $APPCAST_PATH"
