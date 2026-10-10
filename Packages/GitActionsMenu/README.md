# GitActionsMenu

Git actions menu (push/pull/fetch/stash/merge/checkout default/discard/abort).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `GitActionsMenuReducer` / `GitActionsMenuView` — the menu; each item is its own Reducer+View pair (`StashButtonReducer`, `PullButtonReducer`, …). Merge status is fed in by the row (`didCheckGitStatus`), not probed here
- The stash items act on the newest stash taken on the current branch (`StashButtonReducer.State.stash`), so the stash follows the branch. `setCurrentBranch` drops the stash when the branch changes, and the caller re-checks (`refresh`); left in place until the next check, Pop on `master` restored the feature branch's stash. A check reports the branch it looked under (`didFindStash(_:branch:)`) and is ignored if the branch moved since: around a checkout, checks under the old and the new branch overlap. Checks share a cancel id per repository path with `cancelInFlight`. The toolbar's copy of the menu has the same path, but `ifLet`/`forEach` scope cancel ids, so the copy and the row's menu do not cancel each other's checks
- Apply, pop and clear hand `GitStashHelper` the whole entry, which looks it up again by its commit right before running: the stash list is shared by every worktree, so a stash pushed or dropped in another one since the check shifts its `stash@{n}`. Clear's confirmation carries the entry it names (`confirmClear`), so a check landing while the dialog is open cannot swap in another stash to drop
