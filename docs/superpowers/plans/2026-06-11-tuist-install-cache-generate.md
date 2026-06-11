# Tuist Install, Cache & Generate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Install, Cache & Generate" menu item to the Tuist button that runs the three commands sequentially, stopping and reporting an error if any step fails.

**Architecture:** Add a new `installCacheAndGenerate(TuistCacheType)` case to `TuistAction`, add a corresponding action + reducer handler that calls `TuistCommandHelper.runCommand` three times in sequence within one `.run` effect, and add the menu item + progress strings to the view.

**Tech Stack:** Swift 6, SwiftUI, Composable Architecture (TCA), Swift Testing

---

### Task 1: Add `installCacheAndGenerate` to `TuistAction`

**Files:**
- Modify: `Packages/ToolsIntegration/Sources/ToolsIntegration/TuistCommandHelper.swift`

- [ ] **Step 1: Add the new case**

In `TuistAction`, add after `case installUpdate`:

```swift
case installCacheAndGenerate(TuistCacheType)
```

And add its `commandString` (unused by the composite flow, but required for exhaustive switches):

```swift
case .installCacheAndGenerate:
    ""
```

The full updated `commandString` computed property:

```swift
public var commandString: String {
    switch self {
    case .generate:
        "generate"

    case .generateWithoutCache:
        "generate --cache-profile none"

    case .install:
        "install"

    case .installUpdate:
        "install -u"

    case .installCacheAndGenerate:
        ""

    case let .cache(type):
        "cache \(type.commandFlag)".trimmingCharacters(in: .whitespaces)

    case .edit:
        "edit"

    case .inspectDependencies:
        "inspect dependencies --only implicit"
    }
}
```

- [ ] **Step 2: Build to verify no compiler errors**

```bash
swift build --package-path Packages/ToolsIntegration 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/ToolsIntegration/Sources/ToolsIntegration/TuistCommandHelper.swift
git commit -m "feat: add installCacheAndGenerate case to TuistAction"
```

---

### Task 2: Add reducer action and sequential effect

**Files:**
- Modify: `Packages/RepositoryFeature/Sources/RepositoryFeature/TuistButtonReducer.swift`

- [ ] **Step 1: Add the action case**

In the `Action` enum, add after `case cacheTapped`:

```swift
case installCacheAndGenerateTapped
```

- [ ] **Step 2: Add the error title in `actionCompleted`**

In the `actionCompleted` `title` switch, add after `case .cache`:

```swift
case .installCacheAndGenerate: "Tuist Install, Cache & Generate Failed"
```

The full updated title switch:

```swift
let title =
    switch tuistAction {
    case .generate: "Tuist Generate Failed"
    case .generateWithoutCache: "Tuist Generate Failed"
    case .install: "Tuist Install Failed"
    case .installUpdate: "Tuist Install Failed"
    case .cache: "Tuist Cache Failed"
    case .installCacheAndGenerate: "Tuist Install, Cache & Generate Failed"
    case .edit: "Tuist Edit Failed"
    case .inspectDependencies: "Tuist Inspect Failed"
    }
```

- [ ] **Step 3: Add the reducer handler**

After the `cacheTapped` case block and before `editTapped`, add:

```swift
case .installCacheAndGenerateTapped:
    guard state.runningAction == nil else {
        return .none
    }

    let cacheType = state.tuistCacheType
    state.runningAction = .installCacheAndGenerate(cacheType)
    return .run { [
        repositoryPath = state.repositoryPath,
        iosSubfolderPath = state.iosSubfolderPath,
        shouldOpen = state.openXcodeAfterGenerate,
        cacheType,
        misePath = state.misePath,
        runMode = state.tuistRunMode
    ] send in
        let iosFlashscorePath = XcodeProjectDetector.getIosFlashscorePath(
            in: repositoryPath,
            iosSubfolderPath: iosSubfolderPath
        )

        let installResult = await TuistCommandHelper.runCommand(
            .install,
            at: iosFlashscorePath,
            shouldOpenXcode: false,
            misePath: misePath,
            runMode: runMode
        )
        if case let .failure(error) = installResult {
            await send(.actionCompleted(.installCacheAndGenerate(cacheType), .failure(error)))
            return
        }

        let cacheResult = await TuistCommandHelper.runCommand(
            .cache(cacheType),
            at: iosFlashscorePath,
            shouldOpenXcode: false,
            misePath: misePath,
            runMode: runMode
        )
        if case let .failure(error) = cacheResult {
            await send(.actionCompleted(.installCacheAndGenerate(cacheType), .failure(error)))
            return
        }

        let generateResult = await TuistCommandHelper.runCommand(
            .generate,
            at: iosFlashscorePath,
            shouldOpenXcode: shouldOpen,
            misePath: misePath,
            runMode: runMode
        )
        await send(.actionCompleted(.installCacheAndGenerate(cacheType), generateResult))
    }
```

- [ ] **Step 4: Build to verify no compiler errors**

```bash
swift build --package-path Packages/RepositoryFeature 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Packages/RepositoryFeature/Sources/RepositoryFeature/TuistButtonReducer.swift
git commit -m "feat: add installCacheAndGenerateTapped action and sequential effect"
```

---

### Task 3: Update the view — menu item and progress strings

**Files:**
- Modify: `Packages/RepositoryFeature/Sources/RepositoryFeature/TuistButtonView.swift`

- [ ] **Step 1: Add the menu button**

After the "Cache" `Button` block and before the "Edit" `Button` block, add:

```swift
Button {
    store.send(.installCacheAndGenerateTapped)
} label: {
    Label("Install, Cache & Generate", systemImage: "wand.and.stars")
}
```

- [ ] **Step 2: Add progress text**

In `progressText(for:)`, add after `case .cache`:

```swift
case .installCacheAndGenerate:
    "Installing, Caching & Generating..."
```

- [ ] **Step 3: Add progress help text**

In `progressHelpText(for:)`, add after `case .cache`:

```swift
case .installCacheAndGenerate:
    "Running install, cache and generate..."
```

- [ ] **Step 4: Build to verify no compiler errors**

```bash
swift build --package-path Packages/RepositoryFeature 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Packages/RepositoryFeature/Sources/RepositoryFeature/TuistButtonView.swift
git commit -m "feat: add Install, Cache & Generate menu item to Tuist button"
```

---

### Task 4: Run all tests

- [ ] **Step 1: Run ToolsIntegration tests**

```bash
swift test --package-path Packages/ToolsIntegration 2>&1 | grep -E "passed|failed|error:"
```

Expected: all tests pass (or "no tests found" if package has no tests).

- [ ] **Step 2: Run RepositoryFeature tests**

```bash
swift test --package-path Packages/RepositoryFeature 2>&1 | grep -E "passed|failed|error:"
```

Expected: all tests pass.
