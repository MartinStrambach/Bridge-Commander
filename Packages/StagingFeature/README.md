# StagingFeature

File staging panel (detail view, diff, commit).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature
- `FileChangeList` (reducer, `FileChangeListReducer.swift`) / `FileChangeListView` — staged/unstaged file lists. ↑/↓ are handled by the reducer (`moveSelection`), not the native table, so the table never scrolls the new selection into view itself; the view wraps the `List` in a `ScrollViewReader` and calls `scrollTo` (no anchor, so it only moves when the row is off screen) whenever the selection becomes a single file
- `FileDiffViewer` (reducer, `FileDiffViewerReducer.swift`) / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard. `fileId`/`fileIsStaged` name the selection and change as soon as a load starts; the previous diff stays on screen until the response arrives (clearing it would flash the empty state on every arrow-key step), so the view takes the Stage/Unstage side from `diffIsStaged`, which is set together with the diff. A file can be in both lists, so a partially staged file switching sides keeps the same id: only the side tells the two diffs apart. `loadResponse` carries the file and side it answers and is dropped when they are no longer selected. The parent clears the pane with `.clear`, which also cancels a load in flight, never by mutating the child's state
- `CommitReducer` / `CommitView` — commit sheet
- `MergeStatus` (reducer, `MergeStatusReducer.swift`) / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)
