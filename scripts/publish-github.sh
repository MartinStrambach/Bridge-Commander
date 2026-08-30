#!/usr/bin/env bash
# Tag the current commit and publish the notarized DMG as a GitHub release.
# Set DRAFT=1 to create the release as a draft instead of publishing it.

set -euo pipefail

# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if ! command -v gh >/dev/null 2>&1; then
  die "gh not found. Install with: brew install gh"
fi

if ! gh auth status >/dev/null 2>&1; then
  die "gh is not authenticated. Run: gh auth login"
fi

cd "$PROJECT_ROOT"

# The release points at a commit, so refuse to tag anything unreproducible.
if [[ -n "$(git status --porcelain)" ]]; then
  die "working tree is dirty. Commit or stash your changes first."
fi

HEAD_SHA="$(git rev-parse HEAD)"

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [[ -z "$UPSTREAM" ]]; then
  die "current branch has no upstream. Push it first: git push -u origin $(git branch --show-current)"
fi
if ! git merge-base --is-ancestor HEAD "$UPSTREAM" 2>/dev/null; then
  die "HEAD is not pushed to $UPSTREAM. Run 'git push' so the tag points at a published commit."
fi

if [[ ! -f "$DMG_PATH" ]]; then
  die "$DMG_PATH not found. Run 'make release' first."
fi

if ! xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
  die "$DMG_PATH is not stapled. Run 'make release' to build and notarize it."
fi

# Guard against shipping a DMG built from an older checkout. build-release.sh
# stamps the revision; mtimes can't be used because stapling rewrites the DMG.
if [[ ! -f "$REVISION_FILE" ]]; then
  die "$REVISION_FILE missing, so the DMG's source revision is unknown. Rebuild with 'make release'."
fi
BUILT_SHA="$(<"$REVISION_FILE")"
if [[ "$BUILT_SHA" != "$HEAD_SHA" ]]; then
  die "$DMG_PATH was built from ${BUILT_SHA:0:7} but HEAD is ${HEAD_SHA:0:7}. Rebuild with 'make release'."
fi

if gh release view "$VERSION" >/dev/null 2>&1; then
  die "a GitHub release for $VERSION already exists. Bump MARKETING_VERSION or delete it with: gh release delete $VERSION"
fi

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  TAGGED_SHA="$(git rev-list -n1 "$VERSION")"
  if [[ "$TAGGED_SHA" != "$HEAD_SHA" ]]; then
    die "tag $VERSION already exists at $TAGGED_SHA but HEAD is $HEAD_SHA."
  fi
  echo "==> reusing existing tag $VERSION"
else
  echo "==> git tag $VERSION"
  git tag -a "$VERSION" -m "Bridge Commander $VERSION"
fi

echo "==> git push origin $VERSION"
git push origin "refs/tags/$VERSION"

RELEASE_ARGS=(--title "Bridge Commander $VERSION" --generate-notes)
if [[ -n "${DRAFT:-}" ]]; then
  RELEASE_ARGS+=(--draft)
  echo "==> gh release create $VERSION (draft)"
else
  echo "==> gh release create $VERSION"
fi

gh release create "$VERSION" "$DMG_PATH" "${RELEASE_ARGS[@]}"

echo "Published $VERSION: $(gh release view "$VERSION" --json url --jq .url)"
