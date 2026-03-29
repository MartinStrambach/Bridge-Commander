# Bridge Commander - Claude Code Guide

macOS app for managing Git repositories and worktrees. Built with SwiftUI + TCA (Composable Architecture).

## Tech Stack
- Swift 6.0+
- SwiftUI
- Composable Architecture (TCA)
- macOS 26.0+
- Xcode 26.2+

## Project Structure

The app is modularized into 6 SPM packages under `Packages/`, with the thin app target in `BridgeCommander/`.

```
BridgeCommander/          # App entry point (BridgeCommanderApp.swift)
Packages/
  GitCore/                # Git operations, models, process running
  AppUI/                  # Shared UI components and diff viewer
  Settings/               # Settings state, view, and app-wide keys
  ToolsIntegration/       # Xcode, YouTrack, Android Studio, Terminal, Claude Code
  TerminalFeature/        # Embedded terminal (session, view, store)
  RepositoryFeature/      # All repository list/row/detail views and reducers
```

### Package Details

**GitCore** — git primitives and data model
- `ScannedRepository` — core model (path, name, branch, worktree flags, change counts)
- `GitService` — main git client (DI-injected as `GitClient`)
- `GitStatusDetector` — `getBranchAndChanges` returns all status in one git call
- `GitStagingClient` / `GitStagingHelper` — staging operations
- `ProcessRunner` — shells out to git via `runGit()`
- Helpers: `GitWorktreeScanner`, `GitWorktreeCreator`, `GitWorktreeRemover`, `GitMergeDetector`, `GitBranchDetector`, `GitBranchListHelper`, `GitPullHelper`, `GitPushHelper`, `GitFetchHelper`, `GitMergeHelper`, `GitAbortMergeHelper`, `GitStashHelper`

**AppUI** — shared UI components
- `ActionButton`, `ToolButton`, `HeaderButton`, `HunkActionButton`
- `DiffViewer`, `DiffLineView`, `HunkView` — diff display
- `GitOperationProgressView`, `BannerView`, `EmptyStateView`, `ScrollableErrorAlertView`
- `FileChangeRow`, `SectionHeader`, `RepositoryIcon`

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

**TerminalFeature** — embedded terminal panel
- `TerminalSession`, `TerminalViewStore`, `TerminalViewRepresentable`, `TerminalStatusDotView`

**RepositoryFeature** — all feature UI and reducers
- `RepositoryListReducer` / `RepositoryListView` — main list state
- `RepositoryRowReducer` / `RepositoryRowView` — per-row state and actions
- `RepositoryDetailReducer` / `RepositoryDetailView` — file staging panel
- `RepoGroupReducer` / `RepoGroupView` — grouped repo display
- Per-button Reducer+View pairs: `PushButton`, `PullButton`, `FetchButton`, `StashButton`, `MergeMasterButton`, `AbortMergeButton`, `CreateWorktreeButton`, `DeleteWorktreeButton`, `TerminalButton`, `ClaudeCodeButton`, `AndroidStudioButton`, `XcodeProjectButton`, `TuistButton`, `TicketButton`, `ShareButton`
- `CommitReducer` / `CommitView`, `FileDiffViewerReducer` / `FileDiffViewerView`
- `TerminalLayoutReducer` / `TerminalLayoutView` / `TerminalPanelView`
- `GitActionsMenuReducer` / `GitActionsMenuView`
- `MergeStatusReducer` / `MergeStatusBannerView`

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
- `open BridgeCommander.xcworkspace` (workspace includes all packages)
- Or: `xcodebuild -workspace BridgeCommander.xcworkspace -scheme BridgeCommander build`

**Run:**
- ⌘R in Xcode
- Or: `open -a BridgeCommander`

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
