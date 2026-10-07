# GitHosting

GitHub/GitLab pull request + pipeline services.

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `PullRequestClient.fetchDetails` (the row's PR/MR for its branch) and `listOpen` (open PRs/MRs for the create-worktree dialog, `OpenPullRequests.swift`). `listOpen` includes PRs/MRs from forks (GitHub's `isCrossRepository`, GitLab's `sourceProjectId != targetProjectId`) as `isFromFork`, with the fork's owner. Their branch is not on `origin`, so they are checked out from `headRef` — the `refs/pull/<n>/head` / `refs/merge-requests/<iid>/head` that `origin` keeps for every PR/MR. A 200 with a null repository/project throws `.unauthenticated`, as the single fetch does, rather than reading as "no PRs" Each one carries `isAuthoredByViewer` (GitHub's `viewerDidAuthor`; on GitLab, which has no such field, the MR author compared with `currentUser` fetched in the same query), behind the dialog's "Only mine" checkbox (remembered in `worktreeOnlyMyPullRequests`). It filters the listed 50 locally, so an own PR older than the 50 most recently updated does not show
