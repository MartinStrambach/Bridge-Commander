# Design: Close Terminals on Worktree Delete

**Date:** 2026-04-16

## Context

When a user deletes a worktree via the Delete Worktree button, any built-in terminal sessions that were opened for that worktree remain open in the terminal panel as orphaned tabs. These sessions point to a directory that no longer exists, which is confusing and wasteful. The fix closes all built-in terminal sessions associated with a worktree path when that worktree is deleted.

## Architecture

**Single file changed:** `Packages/RepositoryFeature/Sources/RepositoryFeature/RepositoryListReducer.swift`

`RepositoryListReducer` owns all terminal sessions in `state.terminalSessions: IdentifiedArrayOf<TerminalSession>`. Each `TerminalSession` stores a `repositoryPath: String` that exactly matches the worktree's filesystem path. Session cleanup is pure state mutation — no external calls required.

## Current Flow

1. User deletes worktree → `DeleteWorktreeButtonReducer` executes git removal → sends `.didRemoveSuccessfully`
2. `RepositoryRowReducer` sends `.worktreeDeleted`
3. `RepositoryListReducer` matches `.worktrees(.element(_, .worktreeDeleted))` (the `_` discards the path) → triggers a rescan to remove the row from UI state
4. **Terminal sessions are not cleaned up**

## Proposed Change

Split `worktreeDeleted` out of the combined multi-pattern match so the deleted worktree's path can be captured. Before triggering the rescan, remove all terminal sessions whose `repositoryPath` matches the deleted worktree path and update `terminalLayout` accordingly.

### Layout fallback logic (mirrors existing `killTab` pattern)

For each removed session, if it was the active session:
1. Switch to another session for the same repo (if any remain) — shouldn't happen since all sessions for the worktree are being removed, but kept for safety
2. Fall back to any other session across all repos
3. If no sessions remain: set `terminalLayout = nil` (hides the terminal panel)

## Key Files

| File | Change |
|------|--------|
| `Packages/RepositoryFeature/Sources/RepositoryFeature/RepositoryListReducer.swift` | Split `worktreeDeleted` case, add terminal cleanup before rescan |

## Verification

1. Open the app, open a worktree's built-in terminal (one or more tabs)
2. Delete the worktree via the Delete Worktree button and confirm
3. Verify: the terminal tabs for that worktree are removed from the panel
4. Verify: if other repo terminals are open, they remain unaffected
5. Verify: if the deleted worktree's terminal was active and no other sessions exist, the terminal panel closes
6. Verify: if the deleted worktree's terminal was active and other sessions exist, the panel switches to one of them
