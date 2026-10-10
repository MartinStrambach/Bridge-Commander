# StagingFeature

File staging panel (detail view, diff, commit).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature. Every file-list load (refresh, ⌘R, app activation, after a hunk or whole-file stage/unstage) goes through its `loadChanges(state:)` helper under one cancel id, so a newer load cancels an older one still in flight; a separate fetch could answer last and put an older snapshot back. Staging or unstaging whole files carries the selection to restore (`PendingSelection`) in its completion action and stores it only then, so a refresh that answers while the stage is still running cannot use it up on the pre-stage list
- `FileChangeList` (reducer, `FileChangeListReducer.swift`) / `FileChangeListView` — staged/unstaged file lists. ↑/↓ are handled by the reducer (`moveSelection`), not the native table, so the table never scrolls the new selection into view itself; the view wraps the `List` in a `ScrollViewReader` and calls `scrollTo` (no anchor, so it only moves when the row is off screen) whenever the selection becomes a single file
- `FileDiffViewer` (reducer, `FileDiffViewerReducer.swift`) / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard
- `CommitReducer` / `CommitView` — commit sheet
- `MergeStatus` (reducer, `MergeStatusReducer.swift`) / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)
