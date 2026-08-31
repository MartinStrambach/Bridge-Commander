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

# GitHub's generated notes list merged PRs only, so commits pushed directly
# to main would be dropped. Fetch the PR summary from the API and append a
# section with the direct commits: first-parent non-merge commits, minus
# squash-merged PRs, which land as plain commits with a "(#N)" suffix and
# are already covered by the PR summary.
echo "==> generating release notes"
PREV_TAG="$(git describe --tags --abbrev=0 --exclude "$VERSION" HEAD 2>/dev/null || true)"

GENERATE_ARGS=(-f tag_name="$VERSION" -f target_commitish="$HEAD_SHA")
if [[ -n "$PREV_TAG" ]]; then
  GENERATE_ARGS+=(-f previous_tag_name="$PREV_TAG")
  COMMIT_RANGE="$PREV_TAG..HEAD"
else
  COMMIT_RANGE="HEAD"
fi
NOTES_BODY="$(gh api "repos/{owner}/{repo}/releases/generate-notes" "${GENERATE_ARGS[@]}" --jq .body)"

DIRECT_COMMITS="$(git log "$COMMIT_RANGE" --first-parent --no-merges --pretty='* %s (%h)' \
  | grep -Ev '\(#[0-9]+\) \([0-9a-f]+\)$' || true)"

# Keep the generated "Full Changelog" compare link as the closing line.
# When no PRs were merged the API body is only that line, so the removal
# grep may legitimately match nothing.
FULL_CHANGELOG_LINE="$(printf '%s\n' "$NOTES_BODY" | grep '^\*\*Full Changelog\*\*' || true)"
if [[ -n "$FULL_CHANGELOG_LINE" ]]; then
  NOTES_BODY="$(printf '%s\n' "$NOTES_BODY" | grep -v '^\*\*Full Changelog\*\*' || true)"
fi

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
{
  if [[ -n "$NOTES_BODY" ]]; then
    printf '%s\n' "$NOTES_BODY"
  fi
  if [[ -n "$DIRECT_COMMITS" ]]; then
    printf '\n## Direct commits\n%s\n' "$DIRECT_COMMITS"
  fi
  if [[ -n "$FULL_CHANGELOG_LINE" ]]; then
    printf '\n%s\n' "$FULL_CHANGELOG_LINE"
  fi
} > "$NOTES_FILE"

RELEASE_ARGS=(--title "Bridge Commander $VERSION" --notes-file "$NOTES_FILE")
if [[ -n "${DRAFT:-}" ]]; then
  RELEASE_ARGS+=(--draft)
  echo "==> gh release create $VERSION (draft)"
else
  echo "==> gh release create $VERSION"
fi

gh release create "$VERSION" "$DMG_PATH" "${RELEASE_ARGS[@]}"

echo "Published $VERSION: $(gh release view "$VERSION" --json url --jq .url)"
