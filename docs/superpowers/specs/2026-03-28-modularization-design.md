# Bridge Commander Modularization Design

**Date:** 2026-03-28
**Status:** Approved

## Context

Bridge Commander is a macOS SwiftUI + TCA app (~11k LOC, 124 Swift files) structured as a single monolithic Xcode target. All code compiles as one unit — changing any file triggers recompilation of everything that imports it. The goal is to split the codebase into fine-grained local SPM packages to achieve:

- **Faster builds:** Swift compiles packages independently; unchanged modules are skipped
- **Better testability:** Isolated modules can be unit tested with mocked dependencies
- **Cleaner architecture:** Explicit import declarations enforce boundaries; accidental coupling becomes a compile error

## Module Structure

7 local SPM packages in a `Packages/` directory at the project root:

```
Packages/
├── GitCore/
├── AppUI/
├── Settings/
├── ToolsIntegration/
├── TerminalFeature/
├── RepositoryFeature/
└── (App stays as the Xcode target)
```

### Dependency Graph

```
App (Xcode target)
 └─ RepositoryFeature
     ├─ GitCore
     ├─ AppUI
     ├─ ToolsIntegration
     │   └─ GitCore (for ProcessRunner)
     ├─ TerminalFeature
     │   ├─ AppUI
     │   └─ Settings
     └─ Settings
         └─ AppUI
```

All dependencies flow strictly downward. No circular dependencies.

---

## Module Definitions

### GitCore
**Purpose:** Low-level git operations — process execution, git command wrappers, DI clients.

**Files:**
- `Helpers/ProcessRunner.swift`
- `Helpers/Git*.swift` — all ~16 git helpers and detectors (GitStatusDetector, GitStagingHelper, GitPullHelper, GitPushHelper, GitFetchHelper, GitMergeHelper, GitAbortMergeHelper, GitStashHelper, GitWorktreeScanner, GitWorktreeCreator, GitWorktreeRemover, GitBranchDetector, GitBranchListHelper, GitDirectoryResolver, GitEnvironmentHelper, GitMergeDetector)
- `Services/GitClient.swift`, `Services/GitStagingClient.swift`, `Services/ServiceProtocols.swift`
- `Models/GitError.swift`, `Models/ScannedRepository.swift`

**External deps:** Foundation, ComposableArchitecture
**App deps:** None (leaf node)

---

### AppUI
**Purpose:** Reusable SwiftUI components and extensions with no feature-level dependencies.

**Files:**
- `Components/` — all 15 reusable UI components (ActionButton, ToolButton, DiffViewer, FileChangeRow, HunkView, GitOperationProgressView, RepositoryIcon, BannerView, EmptyStateView, ScrollableErrorAlertView, SectionHeader, TerminalStatusDotView, HeaderButton, HunkActionButton, DiffLineView)
- `Extensions/String+Extensions.swift`, `Extensions/AlertState+Extensions.swift`
- `Helpers/ViewExtensions.swift`, `Helpers/WindowSizeHelper.swift`

**External deps:** SwiftUI, ComposableArchitecture (for AlertState)
**App deps:** None (leaf node)

---

### Settings
**Purpose:** App configuration, shared state via `@Shared`, and settings UI.

**Files:**
- `Settings/SettingsReducer.swift`, `Settings/SettingsView.swift`, `Settings/SharedKeys.swift`
- `Models/RepoGroupSettings.swift`, `Models/PeriodicRefreshInterval.swift`, `Models/TerminalColorTheme.swift`, `Models/TerminalOpeningBehavior.swift`

**External deps:** ComposableArchitecture, Sharing
**App deps:** AppUI

---

### ToolsIntegration
**Purpose:** External tool detection, launching, and API integration (Xcode, Claude Code, Android Studio, YouTrack, Tuist).

**Files:**
- `Helpers/XcodeProjectDetector.swift`, `Helpers/XcodeProjectGenerator.swift`
- `Helpers/ClaudeCodeLauncher.swift`, `Helpers/AndroidStudioLauncher.swift`, `Helpers/AndroidStudioDetector.swift`
- `Helpers/TerminalLauncher.swift`
- `Helpers/TuistCommandHelper.swift`
- `Helpers/YouTrackService.swift`
- `Helpers/FileOpener.swift`, `Helpers/BranchNameFormatter.swift`, `Helpers/PermissionChecker.swift`, `Helpers/PipeDataCollector.swift`
- `Services/XcodeClient.swift`, `Services/YouTrackClient.swift`, `Services/LastOpenedDirectoryClient.swift`
- `Models/XcodeProjectState.swift`

**External deps:** Foundation, ComposableArchitecture
**App deps:** GitCore (for ProcessRunner, where needed)

---

### TerminalFeature
**Purpose:** Terminal session management and SwiftTerm view integration (primitives only — no repository coupling).

**Files:**
- `TerminalMode/TerminalViewRepresentable.swift`
- `TerminalMode/TerminalViewStore.swift`
- `TerminalMode/TerminalPanelView.swift`
- `Models/TerminalSession.swift`

> **Note:** `TerminalLayoutReducer.swift` and `TerminalLayoutView.swift` are **not** in this module — they compose terminal primitives with repository detail, so they live in RepositoryFeature.

**External deps:** SwiftUI, ComposableArchitecture, SwiftTerm
**App deps:** AppUI, Settings

---

### RepositoryFeature
**Purpose:** All repository-level feature logic — list, row, detail views and reducers; terminal layout integration.

**Files:**
- `RepositoriesList/` — all files (RepositoryListReducer, RepoGroupReducer, views)
- `RepositoryRow/` — all files including `Buttons/` (all button reducers and views)
- `RepositoryDetail/` — all files (staging, commits, diff viewer)
- `TerminalMode/TerminalLayoutReducer.swift` ← moved from TerminalMode/
- `TerminalMode/TerminalLayoutView.swift` ← moved from TerminalMode/
- `TerminalMode/SidebarRepositoryRowView.swift` ← moved from TerminalMode/

**External deps:** ComposableArchitecture
**App deps:** GitCore, AppUI, ToolsIntegration, TerminalFeature, Settings

---

### App (Xcode target, not a package)
**Purpose:** Entry point only. Creates the root store and sets up the macOS scene.

**Files:**
- `BridgeCommanderApp.swift`
- `Assets.xcassets`, `Info.plist`, `BridgeCommander.entitlements`

**App deps:** RepositoryFeature, Settings

---

## Directory Structure After Migration

```
BridgeCommander/
├── BridgeCommander.xcodeproj
├── App/
│   ├── BridgeCommanderApp.swift
│   ├── Assets.xcassets
│   ├── Info.plist
│   └── BridgeCommander.entitlements
└── Packages/
    ├── GitCore/
    │   ├── Package.swift
    │   └── Sources/GitCore/
    ├── AppUI/
    │   ├── Package.swift
    │   └── Sources/AppUI/
    ├── Settings/
    │   ├── Package.swift
    │   └── Sources/Settings/
    ├── ToolsIntegration/
    │   ├── Package.swift
    │   └── Sources/ToolsIntegration/
    ├── TerminalFeature/
    │   ├── Package.swift
    │   └── Sources/TerminalFeature/
    └── RepositoryFeature/
        ├── Package.swift
        └── Sources/RepositoryFeature/
```

---

## Package.swift Pattern

Each package follows this pattern (example for GitCore):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GitCore", targets: ["GitCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "GitCore",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
```

The root `BridgeCommander.xcodeproj` references each package as a local path dependency via **Add Package → Add Local**.

---

## Access Control Changes

The main mechanical work is making types/functions `public` where they cross module boundaries. Guidelines:

- **Public:** All types, functions, and properties referenced from another module
- **Internal (default):** Implementation details used only within the module
- **The rule:** Start with `internal`; add `public` only when the compiler requires it

Types used across many modules (e.g., `ScannedRepository`, `GitError`) will have many `public` annotations. Button reducers used only within `RepositoryFeature` stay `internal`.

---

## Migration Order

Modules are extracted in dependency order (leaves first):

1. **GitCore** — no app deps, highest reuse, best build time impact
2. **AppUI** — no app deps, pure SwiftUI
3. **Settings** — depends on AppUI only
4. **ToolsIntegration** — depends on GitCore
5. **TerminalFeature** — depends on AppUI + Settings
6. **RepositoryFeature** — depends on all above (move TerminalLayoutReducer/View here first)
7. **App cleanup** — slim down Xcode target to entry point only

Each step: create package → move files → fix `public` access → add to Xcode project → build → fix errors.

---

## Verification

After each module extraction:
- `xcodebuild -project BridgeCommander.xcodeproj -scheme BridgeCommander build` must succeed
- The app must launch and function normally
- No regression in behavior (manual smoke test: scan repos, open terminal, stage files)

After all modules extracted:
- Verify build times improve by touching a file in `AppUI` and confirming `RepositoryFeature` recompiles but `GitCore` does not
- Verify the `App` target directly imports only `RepositoryFeature` and `Settings`
