# Bridge Commander - Claude Code Guide

macOS app for managing Git repositories and worktrees. Built with SwiftUI + TCA (Composable Architecture).

## Tech Stack
- Swift 6.2+ toolchain (every package declares `swift-tools-version: 6.2`; Swift 6 language mode)
- SwiftUI
- Composable Architecture (TCA)
- macOS 26.0+
- Xcode 26.2+

## Project Structure

The app is modularized into SPM packages under `Packages/`, with the thin app target in `BridgeCommander/`.

```
BridgeCommander/          # App entry point (BridgeCommanderApp.swift), Sparkle updater
Packages/
  ActivityLog/            # Shareable log of git commands, network requests and errors (Settings ▸ Activity Log)
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
  HomerFeature/           # Homer console section (instances, sign-in, processes, questions)
  SimulatorFeature/       # iOS simulator pane beside the terminal + MCP server for Claude Code
  RepositoryFeature/      # Repository list/row views and reducers (top-level feature; hosts the window's sections)
```

### App Target

- Debug builds use their own bundle identifier, `com.bridgecommander.BridgeCommander.debug` (display name "Bridge Commander Debug"), so they keep separate user defaults and Application Support data (`Bundle.main.bundleIdentifier` names the folder) — a debug run's saved terminal tabs, tracked repositories and settings never reach the release app. The cost is a separate set of TCC grants (Accessibility, Automation, notifications) for the debug build. Its icon is `AppIconDebug` (the app icon with a red "DEBUG" corner ribbon), generated from `AppIcon` by `scripts/make-debug-icon.py` — rerun it after changing the icon
- `BridgeCommander/Info.plist` is merged over the generated plist (`GENERATE_INFOPLIST_FILE` plus `INFOPLIST_FILE`) and holds only keys with no `INFOPLIST_KEY_` setting: `SUFeedURL`, `SUPublicEDKey` and `SUScheduledCheckInterval` (43200 s = 12 hours; Sparkle's default is a day). Anything else in it would override the generated value. It is excluded from the synchronized folder's resources. `CFBundleVersion` is `$(MARKETING_VERSION)` because Sparkle compares versions by it
- Updater (Sparkle) notes: `BridgeCommander/README.md`

### Package READMEs

Each package's design notes and gotchas live in `Packages/<Name>/README.md` (the app target's in `BridgeCommander/README.md`); ActionButtons and GitActionsMenu have none yet — create one when there is a decision to record there. **Read the README of every package you are about to change before editing it**, and record new non-obvious decisions there, not in this file. Only project-wide information belongs here.

## Architecture

**TCA Pattern:**
- Reducers handle state + side effects
- State is mutated only inside reducers
- Actions trigger changes
- Effects wrap async work

**Dependencies (`@DependencyClient` structs of closures, conforming to `DependencyKey` + `TestDependencyKey`, injected as `@Dependency(XxxClient.self)`):**
- `GitClient` (GitCore, in `GitService.swift`) plus feature-specific git clients (`GitStagingClient`, `GitLogClient`, `GitCommitActionClient`, …)
- `XcodeClient`, `YouTrackClient`, `LastOpenedDirectoryClient` (ToolsIntegration)

## Common Tasks

**New Button:**
- Create `XxxButtonReducer.swift` + `XxxButtonView.swift` in `Packages/RepositoryFeature/Sources/RepositoryFeature/`
- Follow TCA pattern (Reducer + View pair)
- If it goes in the row's action bar: add a `RepositoryRowItem` case (`Settings/RepositoryRowLayout.swift`), render it in `RepositoryRowView`'s item switch and in `RepositoryRowMoreMenu.swift` (see `Packages/RepositoryFeature/README.md`)
- Handle async with `Effect { send in ... }`

**New Git Operation:**
- Add helper in `Packages/GitCore/Sources/GitCore/` (shell out via `ProcessRunner.runGit(arguments:at:)`)
- Expose it through `GitClient` (`GitService.swift`) or the feature-specific client it belongs to (`GitStagingClient`, `GitLogClient`, …)
- New row status goes on `GitPorcelainStatus` and `RepositoryRowReducer.State`, not `ScannedRepository` (which holds only what a scan finds)

**New Service:**
- Add a `@DependencyClient public struct XxxClient: Sendable` of `@Sendable` closures, with `extension XxxClient: DependencyKey { liveValue }` and `TestDependencyKey { testValue }` (see `XcodeService.swift`)
- Implement the live value with a helper in `Packages/ToolsIntegration/Sources/ToolsIntegration/` (or the package it belongs to)
- Use via `@Dependency(XxxClient.self)` in reducers

**Key Files:**
- `BridgeCommander/BridgeCommanderApp.swift` — app entry point
- `GitCore/ScannedRepository.swift` — what a repository scan finds
- `GitCore/GitStatusDetector.swift` — single source of truth for branch status
- `GitCore/GitService.swift` — `GitClient`, the row's git dependency
- `RepositoryFeature/RepositoryListReducer.swift` — main app state
- `RepositoryFeature/RepositoryRowReducer.swift` — per-row actions

## Patterns

**Shell Commands:**
- Use `ProcessRunner.runGit(arguments:at:)` (ProcessExecution package) for git operations; git helpers live in GitCore

**Activity log:**
- New network calls go through `URLSession.loggedData(for:)` and new git calls through `ProcessRunner.runGit`, so they land in the shareable activity log; a dependency client whose errors matter wraps its live closures in `ActivityLog.shared.recordingErrors` (see `Packages/ActivityLog/README.md`)

**Async:**
- Wrap in TCA `Effect { send in ... }`
- Send result actions

**State:**
- View has Reducer
- State flows through reducers
- Views observe store

**UI text scaling (every view):**
- Write `.scaledFont(.caption)` / `.scaledFont(size: 12)` instead of `.font(...)`, and `.buttonStyle(.scaledBordered)` / `.scaledBorderedProminent` / `.scaledAutomatic` on text buttons, so text follows Settings ▸ General ▸ Appearance. Exceptions and the reasons behind them are in `Packages/AppUI/README.md`

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
- Warnings are errors: the app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`, and every `Package.swift` ends with a loop adding `.treatAllWarnings(as: .error)` to all its targets, tests included (a new package needs the same loop). Test targets are compiled only by `swift test`, not by the app build, so run them after touching tests or bumping a dependency that deprecates something. The reverse holds too: the app target enables TCA's `ComposableArchitecture2Deprecations` trait and a package build does not, so `swift build` passes code (e.g. `Effect.concatenate`) that the app build rejects as deprecated — build the app before calling a package change done.
- In `TestStore` assertions, mutate `@Shared` state as `$0.$x.withLock { $0 = … }`; the plain setter is deprecated.
- When adding tests to a package that has none, add a `.testTarget(name: "<Name>Tests", dependencies: ["<Name>"])` to that package's `Package.swift`.
- Prefer pure, dependency-free logic (helpers, models) for unit tests; code that shells out to git is verified by build + manual run.

## Dependencies

**External:**
- swift-composable-architecture, swift-dependencies, swift-sharing (used across packages)
- SwiftTerm (TerminalFeature)
- Sparkle (app target)

**System:**
- SwiftUI, AppKit
- Foundation
- ProcessInfo
- FileManager
- AppleScript (via Process)

## Notes

- Terminal automation requires user permission
- Git must be in PATH
- Worktree detection: looks for `.git` files with gitdir pointers
- Large directory scans may be slow
- Git operations use `ProcessRunner.runGit(arguments:at:)` (ProcessExecution) to shell out to git
- Each package has its own `Package.swift` under `Packages/<Name>/`
- macOS 27 no longer draws the icon of a bare `Label` inside a `Menu` (macOS 26 did). Menus whose items should show icons apply `.labelStyle(.titleAndIcon)` to their content (see `GitActionsMenuView`, `TuistButtonView`). A nested `Menu`'s content does not inherit it and needs its own
