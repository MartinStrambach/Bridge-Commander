# StagingFeature

File staging panel (detail view, diff, commit).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature
- `FileChangeListReducer` / `FileChangeListView` — staged/unstaged file lists. ↑/↓ are handled by the reducer (`moveSelection`), not the native table, so the table never scrolls the new selection into view itself; the view wraps the `List` in a `ScrollViewReader` and calls `scrollTo` (no anchor, so it only moves when the row is off screen) whenever the selection becomes a single file
- `FileDiffViewerReducer` / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard
- `CommitReducer` / `CommitView` — commit sheet
- `MergeStatusReducer` / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)
