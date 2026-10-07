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
BridgeCommander/          # App entry point (BridgeCommanderApp.swift), Sparkle updater
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

### App Target

- Debug builds use their own bundle identifier, `com.bridgecommander.BridgeCommander.debug` (display name "Bridge Commander Debug"), so they keep separate user defaults and Application Support data (`Bundle.main.bundleIdentifier` names the folder) — a debug run's saved terminal tabs, tracked repositories and settings never reach the release app. The cost is a separate set of TCC grants (Accessibility, Automation, notifications) for the debug build. Its icon is `AppIconDebug` (the app icon with a red "DEBUG" corner ribbon), generated from `AppIcon` by `scripts/make-debug-icon.py` — rerun it after changing the icon
- `BridgeCommander/Info.plist` is merged over the generated plist (`GENERATE_INFOPLIST_FILE` plus `INFOPLIST_FILE`) and holds only keys with no `INFOPLIST_KEY_` setting: `SUFeedURL`, `SUPublicEDKey` and `SUScheduledCheckInterval` (43200 s = 12 hours; Sparkle's default is a day). Anything else in it would override the generated value. It is excluded from the synchronized folder's resources. `CFBundleVersion` is `$(MARKETING_VERSION)` because Sparkle compares versions by it
- Updater (Sparkle) notes: `BridgeCommander/README.md`

### Package READMEs

Each package's design notes and gotchas live in `Packages/<Name>/README.md` (the app target's in `BridgeCommander/README.md`). **Read the README of every package you are about to change before editing it**, and record new non-obvious decisions there, not in this file. Only project-wide information belongs here.

## Architecture

**TCA Pattern:**
- Reducers handle state + side effects
- States are immutable
- Actions trigger changes
- Effects wrap async work

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
- Warnings are errors: the app target sets `SWIFT_TREAT_WARNINGS_AS_ERRORS`, and every `Package.swift` ends with a loop adding `.treatAllWarnings(as: .error)` to all its targets, tests included (a new package needs the same loop). Test targets are compiled only by `swift test`, not by the app build, so run them after touching tests or bumping a dependency that deprecates something.
- In `TestStore` assertions, mutate `@Shared` state as `$0.$x.withLock { $0 = … }`; the plain setter is deprecated.
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
- macOS 27 no longer draws the icon of a bare `Label` inside a `Menu` (macOS 26 did). Menus whose items should show icons apply `.labelStyle(.titleAndIcon)` to their content (see `GitActionsMenuView`, `TuistButtonView`). A nested `Menu`'s content does not inherit it and needs its own
