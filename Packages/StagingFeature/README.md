# StagingFeature

File staging panel (detail view, diff, commit).

Design notes and gotchas for this package. Project-wide conventions are in the root `CLAUDE.md`.

## Notes

- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature
- `FileChangeList` (reducer, `FileChangeListReducer.swift`) / `FileChangeListView` — staged/unstaged file lists. ↑/↓ are handled by the reducer (`moveSelection`), not the native table, so the table never scrolls the new selection into view itself; the view wraps the `List` in a `ScrollViewReader` and calls `scrollTo` (no anchor, so it only moves when the row is off screen) whenever the selection becomes a single file
- `FileDiffViewer` (reducer, `FileDiffViewerReducer.swift`) / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard. The diff is mapped to AppUI's models inside the load effect, off the main actor (large diffs hung the window when the reducer did it). A `loadResponse` is dropped unless it is for the file still selected: `clearSelection()` is a plain state mutation and cannot cancel the load. After a hunk action, `isApplyingHunk` drops further hunk actions until the diff reloads (or `RepositoryDetail` sees the write fail) — the hunks on screen are stale until then, and a double click applied an added hunk twice
- Index writes are serialized in `GitStagingClient`'s live value (GitCore's `GitIndexWriteQueue`), not here: queueing keeps every checkbox tick, where a reducer flag would have to drop the later ones. The refresh after a stage/unstage runs under the same cancel ID as every other refresh (`loadChanges`), so the newest refresh always wins
- `CommitReducer` / `CommitView` — commit sheet. When Commit & Push commits but the push fails, it still sends `commitSucceeded`, so the panel reloads without the committed files, and keeps the sheet open for the push alert
- `MergeStatus` (reducer, `MergeStatusReducer.swift`) / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)
