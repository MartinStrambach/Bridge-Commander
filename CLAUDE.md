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
  SimulatorFeature/       # iOS simulator pane beside the terminal + MCP server for Claude Code
  RepositoryFeature/      # Repository list/row views and reducers (top-level feature; hosts the window's sections)
```

The Homer console section is the `HomerFeature` product of a separate repository, https://github.com/MartinStrambach/Homer-console-mac-app (its own modules, tests and a standalone app), which RepositoryFeature depends on by version. Change it there, tag a release, and raise the requirement in `Packages/RepositoryFeature/Package.swift`; to work on both at once, point that dependency at a local checkout (`.package(path:)`) and switch it back before committing.

### App Target

- Debug builds use their own bundle identifier, `com.bridgecommander.BridgeCommander.debug` (display name "Bridge Commander Debug"), so they keep separate user defaults and Application Support data (`Bundle.main.bundleIdentifier` names the folder) — a debug run's saved terminal tabs, tracked repositories and settings never reach the release app. The cost is a separate set of TCC grants (Accessibility, Automation, notifications) for the debug build. Its icon is `AppIconDebug` (the app icon with a red "DEBUG" corner ribbon), generated from `AppIcon` by `scripts/make-debug-icon.py` — rerun it after changing the icon
- `BridgeCommander/Info.plist` is merged over the generated plist (`GENERATE_INFOPLIST_FILE` plus `INFOPLIST_FILE`) and holds only keys with no `INFOPLIST_KEY_` setting: `SUFeedURL`, `SUPublicEDKey` and `SUScheduledCheckInterval` (43200 s = 12 hours; Sparkle's default is a day). Anything else in it would override the generated value. It is excluded from the synchronized folder's resources. `CFBundleVersion` is `$(MARKETING_VERSION)` because Sparkle compares versions by it
- Updater (Sparkle) notes: `BridgeCommander/README.md`

### Package READMEs

Each package's design notes and gotchas live in `Packages/<Name>/README.md` (the app target's in `BridgeCommander/README.md`); ActionButtons and GitActionsMenu have none yet — create one when there is a decision to record there. **Read the README of every package you are about to change before editing it**, and record new non-obvious decisions there, not in this file. Only project-wide information belongs here.

## Architecture

TCA throughout. Dependencies are `@DependencyClient` structs of closures, conforming to `DependencyKey` + `TestDependencyKey`, injected as `@Dependency(XxxClient.self)`:
- `GitClient` (GitCore, in `GitService.swift`) plus feature-specific git clients (`GitStagingClient`, `GitLogClient`, `GitCommitActionClient`, …)
- `XcodeClient`, `YouTrackClient`, `LastOpenedDirectoryClient` (ToolsIntegration)

## Common Tasks

**New Button:**
- Create `XxxButtonReducer.swift` + `XxxButtonView.swift` in `Packages/RepositoryFeature/Sources/RepositoryFeature/`
- If it goes in the row's action bar: add a `RepositoryRowItem` case (`Settings/RepositoryRowLayout.swift`), render it in `RepositoryRowView`'s item switch and in `RepositoryRowMoreMenu.swift` (see `Packages/RepositoryFeature/README.md`)

**New Git Operation:**
- Add helper in `Packages/GitCore/Sources/GitCore/` (shell out via `ProcessRunner.runGit(arguments:at:)`)
- Expose it through `GitClient` (`GitService.swift`) or the feature-specific client it belongs to (`GitStagingClient`, `GitLogClient`, …)
- New row status goes on `GitPorcelainStatus` and `RepositoryRowReducer.State`, not `ScannedRepository` (which holds only what a scan finds)

**New Service:**
- Add a `@DependencyClient public struct XxxClient: Sendable` of `@Sendable` closures, with `extension XxxClient: DependencyKey { liveValue }` and `TestDependencyKey { testValue }` (see `XcodeService.swift`)
- Implement the live value with a helper in `Packages/ToolsIntegration/Sources/ToolsIntegration/` (or the package it belongs to)

**New Package:**
- Start from a small package's `Package.swift` (e.g. `Packages/YouTrackMenu/Package.swift`): it carries the closing settings loop and the TCA deprecation traits. Create `Tests/<Name>Tests/` before declaring the test target, and add a `README.md`
- In Xcode, drag `Packages/<Name>` into the project's Packages group (and add its product to the app target if the app links it); do not hand-write `project.pbxproj` entries
- `scripts/check-packages.sh` (part of `make check`) lists whatever is still missing

**Key Files:**
- `BridgeCommander/BridgeCommanderApp.swift` — app entry point
- `GitCore/ScannedRepository.swift` — what a repository scan finds
- `GitCore/GitStatusDetector.swift` — single source of truth for branch status
- `GitCore/GitService.swift` — `GitClient`, the row's git dependency
- `RepositoryFeature/RepositoryListReducer.swift` — main app state
- `RepositoryFeature/RepositoryRowReducer.swift` — per-row actions

## Patterns

**Activity log:**
- New network calls go through `URLSession.loggedData(for:)` and new git calls through `ProcessRunner.runGit`, so they land in the shareable activity log; a dependency client whose errors matter wraps its live closures in `ActivityLog.shared.recordingErrors` (see `Packages/ActivityLog/README.md`)

**UI text scaling (every view):**
- Write `.scaledFont(.caption)` / `.scaledFont(size: 12)` instead of `.font(...)`, and `.buttonStyle(.scaledBordered)` / `.scaledBorderedProminent` / `.scaledAutomatic` on text buttons, so text follows Settings ▸ General ▸ Appearance. Exceptions and the reasons behind them are in `Packages/AppUI/README.md`

**Menus with icons:**
- macOS 27 no longer draws the icon of a bare `Label` inside a `Menu` (macOS 26 did). Menus whose items should show icons apply `.labelStyle(.titleAndIcon)` to their content (see `GitActionsMenuView`, `TuistButtonView`). A nested `Menu`'s content does not inherit it and needs its own

## Build, Test & Run

**`make check` before calling a change done.** It checks the package setup and the docs, builds the app, and tests the packages changed since `origin/main` plus the packages that depend on them. Each step prints only errors, failures and a result line; full logs go to `$TMPDIR/bridge-commander-check/`. The steps also run alone:
- `make build`: the app, Debug (`scripts/build.sh`; extra arguments go to `xcodebuild`)
- `make test`: the changed packages; `make test PKG=all`, or `PKG="GitCore AppUI"`. It runs TerminalFeature through `xcodebuild test`, because `swift test` cannot build SwiftTerm's Metal shader
- `scripts/check-packages.sh` and `scripts/check-docs.py`. The second fails when a backticked name in CLAUDE.md or a README is gone from the code, or when this file grows past its line budget

**Run:**
- The installed release app: `open -a "Bridge Commander"`
- A Debug build: `BridgeCommander.app` under DerivedData's `Build/Products/Debug/`. It shows as "Bridge Commander Debug" and its process is `BridgeCommander`

**Release:** `RELEASE.md` (`make bump`, `make release`, `make publish`).

**Tests:**
- Tests use Swift Testing (`import Testing`, `@Test`/`#expect`) in per-package `Tests/` targets. Prefer pure, dependency-free logic (helpers, models). Code that shells out to git is verified by build plus a manual run
- Warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS` in the app, `.treatAllWarnings(as: .error)` in every package's closing loop), tests included
- Imports are explicit (MemberImportVisibility), so a file must import every module whose members it uses, often `Foundation`. An import in another file of the module no longer makes them visible
- Packages enable the same TCA deprecation traits as the app target, so `swift build` rejects what the app build rejects. The app build does not compile test targets, so only `make test` catches a deprecated API used in a test
- In `TestStore` assertions, mutate `@Shared` state as `$0.$x.withLock { $0 = … }`; the plain setter is deprecated
