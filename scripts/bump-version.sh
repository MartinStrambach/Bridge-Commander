#!/usr/bin/env bash
# Set MARKETING_VERSION (Debug and Release) and commit "chore: bump version to X".
#
# Usage: scripts/bump-version.sh [x.y.z]
#   Without a version, bumps the patch number (0.9.2 -> 0.9.3).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

pbxproj=BridgeCommander.xcodeproj/project.pbxproj

current=$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION = ([0-9.]+);/\1/p' "$pbxproj" | sort -u)
if [[ $(echo "$current" | wc -l) -ne 1 ]]; then
  echo "Debug and Release disagree on MARKETING_VERSION:" $current >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  version="$1"
else
  IFS=. read -r major minor patch <<<"$current"
  version="$major.$minor.$((patch + 1))"
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Not a version: $version (expected x.y.z)" >&2
  exit 1
fi
if [[ "$version" == "$current" ]]; then
  echo "Already at $version" >&2
  exit 1
fi
if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  echo "The working tree has changes; commit or stash them first, so the bump commit holds only the version." >&2
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" ]]; then
  echo "warning: on $branch, not main; version bumps go straight to main" >&2
fi

sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION = )$current;/\1$version;/" "$pbxproj"
if [[ $(grep -c "MARKETING_VERSION = $version;" "$pbxproj") -ne 2 ]]; then
  echo "Expected two MARKETING_VERSION lines set to $version; check $pbxproj" >&2
  exit 1
fi

git commit -q -m "chore: bump version to $version" -- "$pbxproj"
echo "$current -> $version, committed on $branch."
echo "Next: git push, then make release && make publish (RELEASE.md)."
