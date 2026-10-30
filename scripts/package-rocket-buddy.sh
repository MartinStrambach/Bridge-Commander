#!/usr/bin/env bash
# Package the rocket-buddy Claude Code mod as the zip the app downloads when Settings ▸ Terminal ▸
# Claude Code ▸ Rocket buddy is turned on (see Packages/ToolsIntegration/README.md), and print the
# values to pin in `ClaudeRocketBuddy.release`.
#
#   scripts/package-rocket-buddy.sh [mod folder]             default: ~/Documents/rocket-buddy
#   PUBLISH=1 scripts/package-rocket-buddy.sh [mod folder]   also publish it as a GitHub release
#
# Bump `version` in the mod's .claude-plugin/plugin.json for every change: the release tag is
# rocket-buddy-<version>, and the app installs each version once.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="MartinStrambach/Bridge-Commander"

die() {
	echo "error: $*" >&2
	exit 1
}

source_dir="${1:-$HOME/Documents/rocket-buddy}"
[[ -f "$source_dir/.claude-plugin/plugin.json" ]] || die "$source_dir holds no .claude-plugin/plugin.json"

version="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$source_dir/.claude-plugin/plugin.json")"
tag="rocket-buddy-$version"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Only what Claude Code loads: no tools, tests, or the types the engine writes beside plugin.json.
rsync -a \
	--include '/.claude-plugin/' --include '/.claude-plugin/plugin.json' --exclude '/.claude-plugin/*' \
	--include '/hooks/***' --include '/frames/***' --include '/types/***' --include '/README.md' \
	--exclude '*' \
	"$source_dir/" "$work/rocket-buddy/"

# One timestamp for every entry, so the same files always make the same zip (and SHA-256).
find "$work/rocket-buddy" -exec touch -h -r "$source_dir/.claude-plugin/plugin.json" {} +

zip="$PROJECT_ROOT/build/$tag.zip"
mkdir -p "$(dirname "$zip")"
rm -f "$zip"
# -X leaves out the extra timestamp and owner fields, which differ from run to run.
(cd "$work" && zip -q -X -r "$zip" rocket-buddy)
sha256="$(shasum -a 256 "$zip" | cut -d ' ' -f 1)"

echo "Packaged ${zip#"$PROJECT_ROOT/"}"
echo "Pin in ClaudeRocketBuddy.release:"
echo "  version: \"$version\""
echo "  url: \"https://github.com/$GITHUB_REPO/releases/download/$tag/$tag.zip\""
echo "  sha256: \"$sha256\""

if gh release view "$tag" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
	echo "warning: $tag is published already. Pin its zip's SHA-256, not one printed here; bump the version to publish a change." >&2
	[[ "${PUBLISH:-0}" == "1" ]] && die "not publishing over $tag"
elif [[ "${PUBLISH:-0}" == "1" ]]; then
	# A prerelease that is never "latest": the appcast is fetched from releases/latest.
	gh release create "$tag" "$zip" --repo "$GITHUB_REPO" --title "Rocket buddy $version" \
		--notes "The rocket-buddy Claude Code mod Bridge Commander downloads for Settings ▸ Terminal ▸ Claude Code ▸ Rocket buddy." \
		--prerelease --latest=false
fi
