# Bridge Commander - Claude Code Guide

macOS app for managing Git repositories and worktrees. Built with SwiftUI + TCA (Composable Architecture).

## Tech Stack
- Swift 6.0+
- SwiftUI
- Composable Architecture (TCA)
- macOS 26.0+
- Xcode 26.2+

## Project Structure

The app is modularized into SPM packages under `Packages/`, with the thin app target in `BridgeCommander/`.

```
BridgeCommander/          # App entry point (BridgeCommanderApp.swift)
Packages/
  ProcessExecution/       # Shelling out to external processes (ProcessRunner)
  GitCore/                # Git operations and models
  GitHosting/             # GitHub/GitLab pull request + pipeline services
  AppUI/                  # Shared UI components and diff viewer (+ DiffModelMapping target)
  Settings/               # Settings state, view, and app-wide keys
  ToolsIntegration/       # Xcode, YouTrack, Android Studio, Terminal, Claude Code
  TerminalFeature/        # Embedded terminal (session, view, store)
  ActionButtons/          # Android Studio button Reducer+View pair
  GitActionsMenu/         # Git actions menu (push/pull/fetch/stash/merge/checkout default/discard/abort)
  YouTrackMenu/           # YouTrack ticket menu (move to a reachable state)
  GitGraphFeature/        # Commit graph view + selected commit's diff
  StagingFeature/         # File staging panel (detail view, diff, commit)
  RepositoryFeature/      # Repository list/row views and reducers (top-level feature)
```

### Package Details

**GitCore** — git primitives and data model
- `ScannedRepository` — core model (path, name, branch, worktree flags, change counts)
- `GitService` — main git client (DI-injected as `GitClient`)
- `GitStatusDetector` — `getBranchAndChanges` returns all status in one git call
- `GitStagingClient` / `GitStagingHelper` — staging operations
- `GitCommitDiffClient` / `GitCommitDiffHelper` — read-only: what a single commit changed (`git show`). Merges are diffed against the first parent (`--first-parent`), because git prints no diff for a merge otherwise; a root commit shows every file as an addition. Nothing here writes, so browsing commits never moves HEAD, the index or the working tree
- `GitDiffHunkParser` — shared unified-diff → `DiffHunk` parsing (line numbering + `InlineDiffHighlighter`), used by both the staging and commit diff paths
- `ProcessRunner` — shells out to git via `runGit()`
- Helpers: `GitWorktreeScanner`, `GitWorktreeCreator`, `GitBranchNameSanitizer` (whitespace → underscores for typed branch names), `GitWorktreeRemover`, `GitMergeDetector`, `GitBranchDetector`, `GitDefaultBranchDetector`, `GitBranchListHelper`, `GitPullHelper`, `GitPushHelper`, `GitFetchHelper`, `GitMergeHelper`, `GitCheckoutHelper`, `GitAbortMergeHelper`, `GitStashHelper`
- `GitImageDiffLoader` / `ImageDiffSides` / `ImageFileDetector` — load both versions of a changed image (`git cat-file blob`) so a diff view can render them instead of a binary placeholder. `ImageDiffSource.revision(revision:path:)` is the general side (`<rev>:<path>`); `.head(path:)` is sugar for `HEAD`. `resolve(for:isStaged:)` covers the staging comparisons, `resolve(for:commitHash:)` a commit against its first parent

**AppUI** — shared UI components
- `ActionButton`, `ToolButton`, `HeaderButton`, `HunkActionButton`
- `DiffViewer`, `DiffLineView`, `HunkCard` (`HunkHeaderView`, `HunkFooterView`, `hunkCardRow()`), `ImageDiffView` — diff display (images render side by side as Before/After)
- `DiffViewer` is one `LazyVStack`; each hunk is a `Section` whose header, lines and footer are direct lazy items. Never wrap a hunk's lines in their own stack: a nested `LazyVStack` re-measured every line of a whole-file hunk on each lazy phase change and hung the main thread for minutes (v0.6.6 hang report, 2026-09-06)
- `DiffViewer` has two inits: the staging one takes the hunk stage/unstage/discard closures, `init(diff:)` is read-only and renders hunk headers without action buttons. `FileChangeRow` likewise has `init(file:)` for a row with no staging checkbox
- `GitOperationProgressView`, `BannerView`, `EmptyStateView`, `ScrollableErrorAlertView`
- `FileChangeRow`, `SectionHeader`, `RepositoryIcon`
- The **`DiffModelMapping`** target (same package, separate product) holds the `GitCore.*.toAppUI()` conversions. It is where AppUI and GitCore meet, so the `AppUI` target itself stays free of any git dependency and the mapping is not duplicated per feature. Import it alongside `AppUI` wherever a GitCore diff is rendered

**Settings**
- `SettingsReducer` + `SettingsView`
- `AppSettings` keys via `SharedKeys`
- `PeriodicRefreshInterval`, `TerminalColorTheme`, `TerminalOpeningBehavior`, `TuistCacheType`, `RepoGroupSettings`

**ToolsIntegration** — external tool services
- `ServiceProtocols` — protocol definitions
- `XcodeService`, `YouTrackService`, `LastOpenedDirectoryService`
- `TerminalLauncher`, `ClaudeCodeLauncher`, `AndroidStudioLauncher`
- `XcodeProjectDetector`, `XcodeProjectGenerator`, `XcodeDerivedDataHelper`
- `TuistCommandHelper`, `BranchNameFormatter`, `FileOpener`, `PermissionChecker`
- Terminal.app opens a window at the user's home directory the moment it launches, and a plain `do script` (no target) always makes *another* window — so launching it cold left two windows behind, one at home. `TerminalLauncher.openSystemTerminal` therefore reuses that startup window (`do script … in front window`) when Terminal was not already running, for both the new-window and new-tab behaviors. Terminal's dictionary cannot make a tab (`make new tab` fails with -10000), so a new tab means posting ⌘T — and it must be posted **in-process with `CGEvent`**, not handed to `osascript`. macOS checks the Accessibility grant of whoever posts the event, so an `osascript` child gets checked against `osascript`, which has no grant of its own: it fails with `osascript is not allowed to send keystrokes (-1002)` no matter what the user granted the app, which is why tabs silently came out as windows. `requestNewTerminalTab` gates on `PermissionChecker.isAccessibilityPermitted()` (the app's own grant, what `RepositoryListView`'s Accessibility banner tracks) and posts the event itself
- Because the keystroke is in-process, opening a tab is three steps rather than one script: `prepareScript` activates Terminal and returns the front tab's `tty` (or `""` when it already finished the job), then ⌘T is posted, then `newTabScript` polls until the front window's selected tab is no longer that `tty` and runs the command there. Poll rather than guessing a delay — Terminal reports the new tab asynchronously, and a fixed delay lands the command in the tab that was already there. Both builders are `internal` so the script text is unit-tested. If the keystroke cannot be posted, or the tab never arrives, fall back to a plain `do script`: a window beats opening nothing and beats typing into a tab that may have something running in it

**YouTrackMenu** — YouTrack ticket menu
- `YouTrackButtonReducer` / `YouTrackButtonView` — moves a ticket to a different state
- Offers only the transitions YouTrack reports as reachable (`IssueDetails.stateTransitions`); the row supplies them, this package only applies the chosen one

**TerminalFeature** — embedded terminal panel
- `TerminalSession`, `TerminalViewStore`, `TerminalViewRepresentable`, `TerminalStatusDotView`
- Killing a session must go through `TerminalViewStore.killSession` / `killSessions(notIn:)`, which hang up the shell with SIGHUP. Dropping the pane alone does not close the PTY (SwiftTerm leaves a read pending), and SwiftTerm's `terminate()` sends SIGTERM, which interactive zsh ignores. `RepositoryListView` calls `killSessions(notIn:)` whenever the session ids in state change, so reducer-side removals (worktree deletion) hang up too.

**StagingFeature** — file staging panel
- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature
- `FileChangeListReducer` / `FileChangeListView` — staged/unstaged file lists
- `FileDiffViewerReducer` / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard
- `CommitReducer` / `CommitView` — commit sheet
- `MergeStatusReducer` / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)

**GitGraphFeature** — commit graph
- `GitGraphReducer` / `GitGraphView` — the commit table (`GitGraphLayout` assigns lanes, `GitGraphColumnWidths` persists column widths)
- `CommitDetailReducer` / `CommitDetailView` — the bottom pane: the selected commit's changed files on the left, the selected file's diff on the right, in a read-only `DiffViewer`
- The commit table is a `List(selection:)` (not a `ScrollView` + `LazyVStack`), so selection and ↑/↓ keyboard navigation are native; the list takes focus on open. Rows need `.listRowInsets(EdgeInsets())`, `.listRowSeparator(.hidden)` and `defaultMinListRowHeight = GitGraphRowView.rowHeight` to stay flush — any inter-row gap breaks the vertical lane lines. The "Load More" row is `.selectionDisabled()` so arrow keys skip it, and the column header stays a `Section` header *inside* the list so it keeps the rows' insets
- Use one list-level `.contextMenu(forSelectionType:)`, never per-row `.contextMenu` — ⌘A would make AppKit build every row's menu (the same O(rows²) freeze documented in `FileChangeListView`)
- The selection binding ignores nil writes: the list emits one when it cannot carry selection across a wholesale row replacement, and a background refresh must not close the diff pane
- `selectedCommitHash` is kept on the parent state alongside `commitDetail` on purpose, so a row observes only that one property instead of re-rendering whenever the child loads a file list or diff
- `commitTapped` builds the child state and sends `.commitDetail(.task)` itself rather than relying on the view's `.task`, so re-selecting always reloads even when SwiftUI reuses the pane
- Selection is read-only: it shells out to `git show` only, and never checks anything out

**RepositoryFeature** — top-level feature UI and reducers
- `RepositoryListReducer` / `RepositoryListView` — main list state
- `RepositoryRowReducer` / `RepositoryRowView` — per-row state and actions
- `RepoGroupReducer` / `RepoGroupView` — grouped repo display
- Per-button Reducer+View pairs: `CreateWorktreeButton`, `DeleteWorktreeButton`, `TerminalButton`, `ClaudeCodeButton`, `XcodeProjectButton`, `TuistButton`, `TicketButton`, `ShareButton`, `WebButton`
- `TerminalLayoutReducer` / `TerminalLayoutView` / `TerminalPanelView`

## Architecture

**TCA Pattern:**
- Reducers handle state + side effects
- States are immutable
- Actions trigger changes
- Effects wrap async work

**Core Model (ScannedRepository) — in GitCore:**
- path, name, directory
- isWorktree, branchName, isMergeInProgress
- unstagedChangesCount, stagedChangesCount, unpushedCount, behindCount, hasRemoteBranch

**Git status is fetched in one call:**
- `GitStatusDetector.getBranchAndChanges` runs `git status --porcelain=v2 --branch` and parses everything (branch, staged/unstaged counts, unpushed, behind, remote branch)
- `RepositoryRowReducer.fetchAll` fires 1 git process per row

**Services (protocol-based, DI via `@Dependency`):**
- `GitClient` (git ops, defined in GitCore)
- `XcodeService`, `YouTrackService`, `LastOpenedDirectoryService` (in ToolsIntegration)

## Common Tasks

**New Button:**
- Create `XxxButtonReducer.swift` + `XxxButtonView.swift` in `Packages/RepositoryFeature/Sources/RepositoryFeature/`
- Follow TCA pattern (Reducer + View pair)
- Add to `RepositoryRowView`
- Handle async with `Effect { send in ... }`

**New Git Operation:**
- Add helper in `Packages/GitCore/Sources/GitCore/` (shell out via `ProcessRunner.runGit()`)
- Expose via `GitService` / `GitClient`
- Update `ScannedRepository` model if new state needed

**New Service:**
- Define protocol in `ToolsIntegration/ServiceProtocols.swift`
- Implement in `Packages/ToolsIntegration/Sources/ToolsIntegration/`
- Register as `@Dependency` in the appropriate package
- Use via `@Dependency` in reducers

**Key Files:**
- `BridgeCommander/BridgeCommanderApp.swift` — app entry point
- `GitCore/ScannedRepository.swift` — core data model
- `GitCore/GitStatusDetector.swift` — single source of truth for branch status
- `GitCore/GitService.swift` — git client implementation
- `RepositoryFeature/RepositoryListReducer.swift` — main app state
- `RepositoryFeature/RepositoryRowReducer.swift` — per-row actions

## Patterns

**Shell Commands:**
- Use `ProcessRunner.runGit()` for git operations (in GitCore)

**Async:**
- Wrap in TCA `Effect { send in ... }`
- Send result actions

**State:**
- View has Reducer
- State flows through reducers
- Views observe store

## Build & Run

**Build:**
- `open BridgeCommander.xcodeproj` (the project references all local SPM packages under `Packages/`)
- Or: `xcodebuild -project BridgeCommander.xcodeproj -scheme BridgeCommander -destination 'platform=macOS' build`

**Run:**
- ⌘R in Xcode
- Or: `open -a BridgeCommander`

**Test:**
- Unit tests live in per-package `Tests/` targets and use Swift Testing (`import Testing`, `@Test`/`#expect`).
- Run a single package's tests: `swift test --package-path Packages/<Name>` (e.g. `swift test --package-path Packages/GitCore`).
- When adding tests to a package that has none, add a `.testTarget(name: "<Name>Tests", dependencies: ["<Name>"])` to that package's `Package.swift`.
- Prefer pure, dependency-free logic (helpers, models) for unit tests; code that shells out to git is verified by build + manual run.

## Dependencies

**External:**
- ComposableArchitecture (used across packages)
- SwiftUI

**System:**
- Foundation
- ProcessInfo
- FileManager
- AppleScript (via Process)

## Notes

- Terminal automation requires user permission
- Git must be in PATH
- Worktree detection: looks for `.git` files with gitdir pointers
- Large directory scans may be slow
- Git operations use `ProcessRunner.runGit()` to shell out to git
- Each package has its own `Package.swift` under `Packages/<Name>/`
