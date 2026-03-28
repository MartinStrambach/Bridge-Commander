# Bridge Commander Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the monolithic BridgeCommander Xcode target into 6 local SPM packages (GitCore, AppUI, Settings, ToolsIntegration, TerminalFeature, RepositoryFeature) to enable incremental builds, better testability, and enforced module boundaries.

**Architecture:** Each package lives under `Packages/<Name>/` with its own `Package.swift`. The main Xcode target becomes a thin entry point that imports `RepositoryFeature`. Packages are extracted leaves-first (no app deps first) so each step produces a working build.

**Tech Stack:** Swift 6.0, SwiftUI, ComposableArchitecture 1.25.3, swift-dependencies 1.12.0, swift-sharing 2.8.0, SwiftTerm 1.12.0, macOS 26+

---

## File Structure After Migration

```
BridgeCommander/
├── BridgeCommander.xcodeproj
├── BridgeCommander/                    ← Xcode target source (entry point only after migration)
│   └── BridgeCommanderApp.swift
│   └── Assets.xcassets
│   └── Info.plist
│   └── BridgeCommander.entitlements
├── BridgeCommanderKit/                 ← DELETE (empty, was placeholder)
└── Packages/
    ├── GitCore/
    │   ├── Package.swift
    │   └── Sources/GitCore/            ← ProcessRunner, all Git helpers, GitClient, models
    ├── AppUI/
    │   ├── Package.swift
    │   └── Sources/AppUI/              ← Components/, Extensions/, ViewExtensions
    ├── Settings/
    │   ├── Package.swift
    │   └── Sources/Settings/           ← SettingsReducer/View/SharedKeys + config models
    ├── ToolsIntegration/
    │   ├── Package.swift
    │   └── Sources/ToolsIntegration/   ← tool launchers, Xcode/YouTrack/Tuist services
    ├── TerminalFeature/
    │   ├── Package.swift
    │   └── Sources/TerminalFeature/    ← SwiftTerm view, session store, TerminalSession
    └── RepositoryFeature/
        ├── Package.swift
        └── Sources/RepositoryFeature/  ← all feature reducers/views + TerminalLayoutReducer
```

---

## How to Add a Local Package to the Xcode Project

After creating each package directory, add it to the Xcode project:

1. Open `BridgeCommander.xcodeproj` in Xcode
2. **File → Add Package Dependencies…**
3. Click **"Add Local…"** (bottom-left of the dialog)
4. Navigate to and select `Packages/<PackageName>/`
5. In the "Add to Target" column, check **BridgeCommander**
6. Click **Add Package**

After adding, the package product appears in the target's **Frameworks, Libraries, and Embedded Content** section. If it doesn't auto-add, drag it there manually from the project navigator.

---

## Access Control Workflow

After moving files to a new package, build the project. Every error of the form:
```
'SomeType' is inaccessible due to 'internal' protection level
```
...means that type/init/function needs `public`. Fix them as the compiler reports them. The pattern is:

- `public struct SomeType { ... }` — type definition
- `public init(...)` — initializers (required even when struct is public)
- `public var property: Type` — stored/computed properties
- `public func method()` — methods
- Files in the same package don't need `public` — only cross-package access does

---

## Task 1: Prepare Project Structure

**Files:**
- Delete: `BridgeCommanderKit/` (empty directory)
- Create: `Packages/` directory structure

- [ ] **Step 1: Remove the empty BridgeCommanderKit placeholder**

```bash
rm -rf /Users/martin.strambach/Documents/bridge_commander/BridgeCommanderKit
```

- [ ] **Step 2: Create the Packages root directory**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages
```

- [ ] **Step 3: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "chore: remove empty BridgeCommanderKit, add Packages/ directory"
```

---

## Task 2: Extract GitCore

**Purpose:** All git process execution, helpers, DI clients, and core models.

**Files to move** (from `BridgeCommander/` to `Packages/GitCore/Sources/GitCore/`):
- `Helpers/ProcessRunner.swift`
- `Helpers/GitStatusDetector.swift`
- `Helpers/GitStagingHelper.swift`
- `Helpers/GitPullHelper.swift`
- `Helpers/GitPushHelper.swift`
- `Helpers/GitFetchHelper.swift`
- `Helpers/GitMergeHelper.swift`
- `Helpers/GitAbortMergeHelper.swift`
- `Helpers/GitStashHelper.swift`
- `Helpers/GitWorktreeScanner.swift`
- `Helpers/GitWorktreeCreator.swift`
- `Helpers/GitWorktreeRemover.swift`
- `Helpers/GitBranchDetector.swift`
- `Helpers/GitBranchListHelper.swift`
- `Helpers/GitDirectoryResolver.swift`
- `Helpers/GitEnvironmentHelper.swift`
- `Helpers/GitMergeDetector.swift`
- `Services/GitService.swift`
- `Services/GitStagingClient.swift`
- `Services/ServiceProtocols.swift` ← contains `CodeReviewState`, `TicketState`, `IssueDetails`, plus YouTrack/Xcode protocol definitions. Move the entire file here for now; in Task 5 you'll re-export or duplicate the YouTrack-specific parts if needed (compiler will guide you)
- `Models/GitError.swift`
- `Models/ScannedRepository.swift`

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/GitCore/Sources/GitCore
```

Create `Packages/GitCore/Package.swift`:

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
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.12.0"),
    ],
    targets: [
        .target(
            name: "GitCore",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Move files into the package**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

mv BridgeCommander/Helpers/ProcessRunner.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitStatusDetector.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitStagingHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitPullHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitPushHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitFetchHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitMergeHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitAbortMergeHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitStashHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitWorktreeScanner.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitWorktreeCreator.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitWorktreeRemover.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitBranchDetector.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitBranchListHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitDirectoryResolver.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitEnvironmentHelper.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Helpers/GitMergeDetector.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Services/GitService.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Services/GitStagingClient.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Services/ServiceProtocols.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Models/GitError.swift Packages/GitCore/Sources/GitCore/
mv BridgeCommander/Models/ScannedRepository.swift Packages/GitCore/Sources/GitCore/
```

- [ ] **Step 3: Add GitCore local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/GitCore/`.

- [ ] **Step 4: Build and fix access control errors**

In Xcode press ⌘B. For each error `'X' is inaccessible due to 'internal' protection level`, add `public` to that type/init/property/function in the file inside `Packages/GitCore/Sources/GitCore/`.

Key types that will definitely need `public`:
- `ScannedRepository` struct + all its properties + its `init`
- `GitError` enum + all cases
- `GitBranchAndChanges` struct (if it exists) + all properties + init
- All `@DependencyClient`-generated clients (`GitClient`, `GitStagingClient`) — the struct and all endpoint properties
- `ProcessRunner` static functions
- `GitStatusDetector` static functions (`getBranchAndChanges`, etc.)
- `GitStagingHelper` functions
- All other Git*Helper static functions that are called from RepositoryFeature

Build repeatedly until the app compiles cleanly.

- [ ] **Step 5: Verify app still launches**

Run the app (⌘R) and verify: repo list loads, scanning works, no crashes on launch.

- [ ] **Step 6: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract GitCore SPM package"
```

---

## Task 3: Extract AppUI

**Purpose:** Reusable SwiftUI components and Swift extensions with no feature dependencies.

**Files to move** (from `BridgeCommander/` to `Packages/AppUI/Sources/AppUI/`):

All of `Components/`:
- `Components/ActionButton.swift`
- `Components/ToolButton.swift`
- `Components/HeaderButton.swift`
- `Components/HunkActionButton.swift`
- `Components/DiffViewer.swift`
- `Components/DiffLineView.swift`
- `Components/FileChangeRow.swift`
- `Components/HunkView.swift`
- `Components/GitOperationProgressView.swift`
- `Components/RepositoryIcon.swift`
- `Components/BannerView.swift`
- `Components/EmptyStateView.swift`
- `Components/ScrollableErrorAlertView.swift`
- `Components/SectionHeader.swift`
- `Components/TerminalStatusDotView.swift`

Plus utility files:
- `Extensions/String+Extensions.swift`
- `Extensions/AlertState+Extensions.swift`
- `Helpers/ViewExtensions.swift`
- `Helpers/WindowSizeHelper.swift`

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/AppUI/Sources/AppUI
```

Create `Packages/AppUI/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
    ],
    targets: [
        .target(
            name: "AppUI",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Move files into the package**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

mv BridgeCommander/Components/ActionButton.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/ToolButton.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/HeaderButton.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/HunkActionButton.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/DiffViewer.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/DiffLineView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/FileChangeRow.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/HunkView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/GitOperationProgressView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/RepositoryIcon.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/BannerView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/EmptyStateView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/ScrollableErrorAlertView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/SectionHeader.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Components/TerminalStatusDotView.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Extensions/String+Extensions.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Extensions/AlertState+Extensions.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Helpers/ViewExtensions.swift Packages/AppUI/Sources/AppUI/
mv BridgeCommander/Helpers/WindowSizeHelper.swift Packages/AppUI/Sources/AppUI/
```

- [ ] **Step 3: Add AppUI local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/AppUI/`.

- [ ] **Step 4: Build and fix access control errors**

Press ⌘B. Add `public` to all types/functions/properties reported as inaccessible.

Key items that will need `public`:
- All SwiftUI `View` structs in Components (the struct + `body` property)
- All extension methods on `String` and `AlertState`
- Any helper functions in ViewExtensions or WindowSizeHelper used from feature code

Also add `import AppUI` to any file in the main target that uses these components (the compiler will tell you which files).

Build repeatedly until clean.

- [ ] **Step 5: Verify app still launches**

Run the app (⌘R) and verify the UI renders correctly.

- [ ] **Step 6: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract AppUI SPM package"
```

---

## Task 4: Extract Settings

**Purpose:** App configuration models, `@Shared` keys, and the Settings view/reducer.

**Files to move** (from `BridgeCommander/` to `Packages/Settings/Sources/Settings/`):
- `Settings/SettingsReducer.swift`
- `Settings/SettingsView.swift`
- `Settings/SharedKeys.swift` (or equivalent file defining `@Shared` keys)
- `Models/RepoGroupSettings.swift`
- `Models/PeriodicRefreshInterval.swift`
- `Models/TerminalColorTheme.swift`
- `Models/TerminalOpeningBehavior.swift`

> **Note:** If `SharedKeys.swift` doesn't exist under `Settings/`, search the `Settings/` folder and `Models/` for the file that defines `AppStorage`/`@Shared` keys.

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/Settings/Sources/Settings
```

Create `Packages/Settings/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Settings",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/pointfreeco/swift-sharing", exact: "2.8.0"),
        .package(path: "../AppUI"),
    ],
    targets: [
        .target(
            name: "Settings",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "AppUI", package: "AppUI"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Find and move all Settings-related files**

First, confirm which files exist under `BridgeCommander/Settings/`:

```bash
ls /Users/martin.strambach/Documents/bridge_commander/BridgeCommander/Settings/
```

Then move them:

```bash
cd /Users/martin.strambach/Documents/bridge_commander

# Move all files from Settings/ directory
for f in BridgeCommander/Settings/*.swift; do
  mv "$f" Packages/Settings/Sources/Settings/
done

# Move config models
mv BridgeCommander/Models/RepoGroupSettings.swift Packages/Settings/Sources/Settings/
mv BridgeCommander/Models/PeriodicRefreshInterval.swift Packages/Settings/Sources/Settings/
mv BridgeCommander/Models/TerminalColorTheme.swift Packages/Settings/Sources/Settings/
mv BridgeCommander/Models/TerminalOpeningBehavior.swift Packages/Settings/Sources/Settings/
```

- [ ] **Step 3: Add Settings local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/Settings/`.

- [ ] **Step 4: Build and fix access control errors**

Press ⌘B. Add `public` to all reported inaccessible types.

Key items:
- `RepoGroupSettings` struct + properties + init
- `PeriodicRefreshInterval` enum + cases
- `TerminalColorTheme` enum + cases
- `TerminalOpeningBehavior` enum + cases
- `SettingsReducer` (State, Action, body) — if referenced from App
- Any `@SharedKey` type definitions

Add `import Settings` to files in the main target that use these types.

- [ ] **Step 5: Verify app still launches and settings open correctly**

Run the app (⌘R). Open Settings (⌘,) and confirm the settings sheet renders.

- [ ] **Step 6: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract Settings SPM package"
```

---

## Task 5: Extract ToolsIntegration

**Purpose:** External tool detection, launching, and API clients (Xcode, Claude Code, Android Studio, YouTrack, Tuist).

**Files to move** (from `BridgeCommander/` to `Packages/ToolsIntegration/Sources/ToolsIntegration/`):
- `Helpers/XcodeProjectDetector.swift`
- `Helpers/XcodeProjectGenerator.swift`
- `Helpers/XcodeDerivedDataHelper.swift`
- `Helpers/ClaudeCodeLauncher.swift`
- `Helpers/AndroidStudioLauncher.swift`
- `Helpers/AndroidStudioDetector.swift`
- `Helpers/TerminalLauncher.swift`
- `Helpers/TuistCommandHelper.swift`
- `Helpers/YouTrackService.swift`
- `Helpers/FileOpener.swift`
- `Helpers/BranchNameFormatter.swift`
- `Helpers/PermissionChecker.swift`
- `Helpers/PipeDataCollector.swift` ← **check first**: if any GitCore helper imports `PipeDataCollector`, move it to GitCore instead and remove from this list
- `Services/XcodeService.swift`
- `Services/YouTrackServiceImpl.swift`
- `Services/LastOpenedDirectoryService.swift`
- `Models/XcodeProjectState.swift`

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/ToolsIntegration/Sources/ToolsIntegration
```

Create `Packages/ToolsIntegration/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToolsIntegration",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ToolsIntegration", targets: ["ToolsIntegration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", exact: "1.12.0"),
        .package(path: "../GitCore"),
    ],
    targets: [
        .target(
            name: "ToolsIntegration",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesMacros", package: "swift-dependencies"),
                .product(name: "GitCore", package: "GitCore"),
            ]
        ),
    ]
)
```

> **Note:** The dependency on `GitCore` is for `ProcessRunner`. If `ToolsIntegration` files don't actually use `ProcessRunner` directly (they may use `Process` or `NSWorkspace` instead), remove the `GitCore` dependency from `Package.swift` to keep the module boundary clean.

- [ ] **Step 2: Move files into the package**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

mv BridgeCommander/Helpers/XcodeProjectDetector.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/XcodeProjectGenerator.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/XcodeDerivedDataHelper.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/ClaudeCodeLauncher.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/AndroidStudioLauncher.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/AndroidStudioDetector.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/TerminalLauncher.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/TuistCommandHelper.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/YouTrackService.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/FileOpener.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/BranchNameFormatter.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/PermissionChecker.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Helpers/PipeDataCollector.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Services/XcodeService.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Services/YouTrackServiceImpl.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Services/LastOpenedDirectoryService.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
mv BridgeCommander/Models/XcodeProjectState.swift Packages/ToolsIntegration/Sources/ToolsIntegration/
```

- [ ] **Step 3: Add ToolsIntegration local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/ToolsIntegration/`.

- [ ] **Step 4: Build and fix access control errors**

Press ⌘B. Add `public` to all reported inaccessible types.

Key items:
- `XcodeProjectState` + init
- `XcodeClient` DI client and its endpoint properties
- `YouTrackClient` DI client
- `LastOpenedDirectoryClient` DI client
- `IssueDetails` struct (from ServiceProtocols — check if this was moved to GitCore or needs to be here)
- Launcher functions (e.g., `TerminalLauncher.open(path:)`)

Add `import ToolsIntegration` to files in the main target that use these.

- [ ] **Step 5: Verify app still launches and tool buttons work**

Run the app (⌘R). Click the Terminal, Xcode, and Claude Code buttons on a repo row. Verify they launch correctly.

- [ ] **Step 6: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract ToolsIntegration SPM package"
```

---

## Task 6: Extract TerminalFeature

**Purpose:** SwiftTerm view integration and terminal session state — pure primitives with no repository coupling.

**Files to move** (from `BridgeCommander/TerminalMode/` to `Packages/TerminalFeature/Sources/TerminalFeature/`):
- `TerminalMode/TerminalViewRepresentable.swift`
- `TerminalMode/TerminalViewStore.swift`
- `TerminalMode/TerminalPanelView.swift`
- `Models/TerminalSession.swift`

**Files that stay in `BridgeCommander/TerminalMode/`** (moved to RepositoryFeature in Task 7):
- `TerminalLayoutReducer.swift`
- `TerminalLayoutView.swift`
- `SidebarRepositoryRowView.swift`

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/TerminalFeature/Sources/TerminalFeature
```

Create `Packages/TerminalFeature/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TerminalFeature", targets: ["TerminalFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.12.0"),
        .package(path: "../AppUI"),
        .package(path: "../Settings"),
    ],
    targets: [
        .target(
            name: "TerminalFeature",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "AppUI", package: "AppUI"),
                .product(name: "Settings", package: "Settings"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Move files into the package**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

mv BridgeCommander/TerminalMode/TerminalViewRepresentable.swift Packages/TerminalFeature/Sources/TerminalFeature/
mv BridgeCommander/TerminalMode/TerminalViewStore.swift Packages/TerminalFeature/Sources/TerminalFeature/
mv BridgeCommander/TerminalMode/TerminalPanelView.swift Packages/TerminalFeature/Sources/TerminalFeature/
mv BridgeCommander/Models/TerminalSession.swift Packages/TerminalFeature/Sources/TerminalFeature/
```

- [ ] **Step 3: Add TerminalFeature local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/TerminalFeature/`.

- [ ] **Step 4: Build and fix access control errors**

Press ⌘B. Add `public` to all reported inaccessible types.

Key items:
- `TerminalSession` struct + init + all properties
- `TerminalViewStore` + all public interface
- `TerminalViewRepresentable` SwiftUI view struct
- `TerminalPanelView` SwiftUI view struct

Add `import TerminalFeature` to files that use these.

- [ ] **Step 5: Verify terminal still works**

Run the app (⌘R). Open the terminal panel for a repo. Verify the terminal renders and accepts input.

- [ ] **Step 6: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract TerminalFeature SPM package"
```

---

## Task 7: Extract RepositoryFeature

**Purpose:** All repository feature logic — list, row, detail views and reducers — plus the terminal layout integration that composes TerminalFeature with repository detail.

**Files to move** (from `BridgeCommander/` to `Packages/RepositoryFeature/Sources/RepositoryFeature/`):

All of `RepositoriesList/`:
```bash
mv BridgeCommander/RepositoriesList/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
```

All of `RepositoryRow/` (including `Buttons/` subdirectory):
```bash
mv BridgeCommander/RepositoryRow/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/RepositoryRow/Buttons/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
```

All of `RepositoryDetail/`:
```bash
mv BridgeCommander/RepositoryDetail/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
```

Remaining TerminalMode files (layout coordination):
```bash
mv BridgeCommander/TerminalMode/TerminalLayoutReducer.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/TerminalMode/TerminalLayoutView.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/TerminalMode/SidebarRepositoryRowView.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
```

- [ ] **Step 1: Create package directory and Package.swift**

```bash
mkdir -p /Users/martin.strambach/Documents/bridge_commander/Packages/RepositoryFeature/Sources/RepositoryFeature
```

Create `Packages/RepositoryFeature/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RepositoryFeature",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "RepositoryFeature", targets: ["RepositoryFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", exact: "1.25.3"),
        .package(path: "../GitCore"),
        .package(path: "../AppUI"),
        .package(path: "../Settings"),
        .package(path: "../ToolsIntegration"),
        .package(path: "../TerminalFeature"),
    ],
    targets: [
        .target(
            name: "RepositoryFeature",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "GitCore", package: "GitCore"),
                .product(name: "AppUI", package: "AppUI"),
                .product(name: "Settings", package: "Settings"),
                .product(name: "ToolsIntegration", package: "ToolsIntegration"),
                .product(name: "TerminalFeature", package: "TerminalFeature"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Move all feature files**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

mv BridgeCommander/RepositoriesList/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/RepositoryRow/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/RepositoryRow/Buttons/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/RepositoryDetail/*.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/TerminalMode/TerminalLayoutReducer.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/TerminalMode/TerminalLayoutView.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
mv BridgeCommander/TerminalMode/SidebarRepositoryRowView.swift Packages/RepositoryFeature/Sources/RepositoryFeature/
```

- [ ] **Step 3: Add `import` statements inside the moved files**

Each moved file that uses types from other modules needs an explicit import. Open each file and add imports at the top. The compiler will guide you, but common patterns:

Files using `ScannedRepository`, `GitClient`, `GitError` → add `import GitCore`
Files using `ActionButton`, `DiffViewer`, etc. → add `import AppUI`
Files using `TerminalSession`, `TerminalViewRepresentable` → add `import TerminalFeature`
Files using `XcodeClient`, `YouTrackClient`, `LastOpenedDirectoryClient` → add `import ToolsIntegration`
Files using `RepoGroupSettings`, `PeriodicRefreshInterval`, `@Shared` keys → add `import Settings`

- [ ] **Step 4: Add RepositoryFeature local package to Xcode project**

Follow the "How to Add a Local Package" instructions above, selecting `Packages/RepositoryFeature/`.

- [ ] **Step 5: Build and fix all errors**

This is the largest fix step. Press ⌘B and work through errors systematically:

1. **"Cannot find type 'X' in scope"** → add `import ModuleName` at the top of the file
2. **"'X' is inaccessible due to 'internal' protection level"** → add `public` to X in its definition file
3. **"Initializer is inaccessible"** → add `public` to the `init`

Key `public` annotations needed in RepositoryFeature for `BridgeCommanderApp.swift` to compile:
- `RepositoryListReducer` (State, Action, body)
- `RepositoryListView`
- `RepositoryListReducer.State` initializer

Iterate: build → fix errors → build → fix errors until clean.

- [ ] **Step 6: Verify full app functionality**

Run the app (⌘R) and test:
- Repo list loads and scans correctly
- Click each button (Terminal, Xcode, Claude Code, Android Studio, YouTrack, Tuist)
- Open staging detail view, stage/unstage a file
- Open the terminal panel
- Open Settings

- [ ] **Step 7: Commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "feat: extract RepositoryFeature SPM package"
```

---

## Task 8: App Target Cleanup

**Purpose:** The main Xcode target should now only contain the entry point. Clean up any leftover files and empty directories.

- [ ] **Step 1: Verify the BridgeCommander target source folder is clean**

Check what's left in `BridgeCommander/`:

```bash
find /Users/martin.strambach/Documents/bridge_commander/BridgeCommander -name "*.swift" | sort
```

Expected: only `BridgeCommanderApp.swift` remains.

If any `.swift` files remain that belong to an extracted package, move them to the correct package's `Sources/` directory and fix access control.

- [ ] **Step 2: Clean up empty directories**

```bash
cd /Users/martin.strambach/Documents/bridge_commander

# Remove empty subdirectories in BridgeCommander/
find BridgeCommander -type d -empty -not -path "BridgeCommander/.xcassets*" -delete
```

- [ ] **Step 3: Ensure BridgeCommanderApp.swift imports only what it needs**

Open `BridgeCommander/BridgeCommanderApp.swift`. It should import:
- `import SwiftUI`
- `import ComposableArchitecture`
- `import RepositoryFeature`
- `import Settings` (if `SettingsReducer` is used at app level)

Remove any other imports.

- [ ] **Step 4: Final build verification**

```bash
xcodebuild -project /Users/martin.strambach/Documents/bridge_commander/BridgeCommander.xcodeproj \
  -scheme BridgeCommander \
  -configuration Debug \
  build | tail -20
```

Expected output ends with: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Smoke test the app**

Run the app (⌘R) and perform a full smoke test:
1. App launches without crash
2. Directory scanning works
3. Repository list populates
4. Terminal panel opens
5. Staging detail view opens and shows file changes
6. Settings sheet opens
7. All tool buttons (Terminal, Xcode, Claude Code) are clickable

- [ ] **Step 6: Final commit**

```bash
cd /Users/martin.strambach/Documents/bridge_commander
git add -A
git commit -m "chore: clean up app target after modularization

All feature code now lives in local SPM packages under Packages/.
App target contains only the entry point (BridgeCommanderApp.swift)."
```

---

## Troubleshooting

**"No such module 'X'"** when building a package:
- The package hasn't been added to the Xcode project yet, or the product name in Package.swift doesn't match the import. Double-check `products: [.library(name: "X", ...)]` matches `import X`.

**Circular dependency error from SPM:**
- Check that no package's `dependencies` array references a package that also (directly or transitively) references it back. The dependency graph must be a DAG.

**"Expression is ambiguous without more context" after adding public:**
- Usually means a type exists in two modules. Check if you accidentally have duplicate files (one in the package, one still in the main target). Remove the one from the main target.

**Build times don't improve after modularization:**
- Xcode may still be doing a full build the first time. Make a change to `AppUI/DiffViewer.swift`, build, then check the build log — only `AppUI` and `RepositoryFeature` (the importer) should recompile.
