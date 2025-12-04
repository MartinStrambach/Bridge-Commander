# Bridge Commander - Claude Code Guide

This document provides essential information for Claude Code (and other AI assistants) working with the Bridge Commander project.

## Project Overview

Bridge Commander is a macOS application for managing Git repositories and worktrees, built with SwiftUI and the Composable Architecture (TCA). It allows users to scan directories for repositories, display them in a clean interface, and perform common Git operations like opening repositories in Terminal, Finder, or IDEs.

## Architecture

### Technology Stack
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **State Management**: Composable Architecture (TCA)
- **Target OS**: macOS 13.0+
- **IDE**: Xcode 26.0+

### Project Structure

```
BridgeCommander/
├── BridgeCommanderApp.swift              # App entry point, window configuration
├── Models/
│   ├── TCAModels.swift                   # Core data models (ScannedRepository)
│   └── XcodeProjectState.swift           # Xcode project detection state
├── Services/
│   ├── ServiceProtocols.swift            # Protocol definitions for all services
│   ├── Dependencies.swift                # Dependency injection setup
│   ├── GitService.swift                  # Git operations and queries
│   ├── XcodeService.swift                # Xcode project detection
│   ├── YouTrackServiceImpl.swift          # YouTrack integration
│   └── LastOpenedDirectoryService.swift  # Recent directory persistence
├── RepositoriesList/
│   ├── RepositoryListView.swift          # Main list view (TCA)
│   └── RepositoryListReducer.swift       # List state management
├── Components/
│   ├── ActionButton.swift                # Simple icon-only action button
│   ├── ToolButton.swift                  # Labeled tool button with icon
│   └── GitOperationProgressView.swift    # Progress indicator for git operations
├── RepositoryRow/
│   ├── RepositoryRowView.swift           # Individual repo row component
│   ├── RepositoryRowReducer.swift        # Row state management
│   └── Buttons/                          # Action buttons for each repo
│       ├── TerminalButtonView/Reducer.swift
│       ├── XcodeProjectButtonView/Reducer.swift
│       ├── ClaudeCodeButtonView/Reducer.swift
│       ├── AndroidStudioButtonView/Reducer.swift
│       ├── TicketButtonView/Reducer.swift
│       ├── GitActionsMenuView/Reducer.swift # Menu composing git actions
│       ├── PullButtonView/Reducer.swift      # Git pull action
│       ├── MergeMasterButtonView/Reducer.swift # Merge master action
│       ├── CreateWorktreeButtonView/Reducer.swift
│       ├── DeleteWorktreeButtonView/Reducer.swift
│       └── ShareButtonView/Reducer.swift
├── Helpers/
│   ├── GitDetector.swift                 # Git repository detection logic
│   ├── GitBranchDetector.swift           # Current branch detection
│   ├── GitStatusDetector.swift           # Staged/unstaged changes detection
│   ├── GitMergeDetector.swift            # Merge-in-progress detection
│   ├── GitRemoteBranchDetector.swift     # Remote branch tracking detection
│   ├── GitMergeMasterHelper.swift        # Merge master branch logic
│   ├── GitPullHelper.swift               # Git pull operation logic
│   ├── GitWorktreeCreator.swift          # Worktree creation logic
│   ├── GitWorktreeRemover.swift          # Worktree deletion logic
│   ├── XcodeProjectDetector.swift        # .xcodeproj detection
│   ├── XcodeProjectGenerator.swift       # Xcode project generation
│   ├── AndroidStudioDetector.swift       # Android Studio project detection
│   ├── AndroidStudioLauncher.swift       # Android Studio launching
│   ├── ClaudeCodeLauncher.swift          # Claude Code CLI integration
│   ├── TerminalLauncher.swift            # Terminal.app automation
│   ├── YouTrackService.swift             # YouTrack API abstraction
│   └── BranchNameFormatter.swift         # Branch name formatting utilities
├── Environment/
│   └── AbbreviationMode.swift            # UI text abbreviation mode
└── Settings/
    ├── SettingsView.swift                # Settings UI
    └── AppSettings.swift                 # Settings persistence and state
```

## Key Concepts

### TCA (Composable Architecture)
The app uses TCA for state management:
- **Reducers**: Handle state changes and side effects (RepositoryListReducer, RepositoryRowReducer)
- **States**: Immutable data structures (ScannedRepository)
- **Actions**: Events that trigger state changes
- **Effects**: Async operations wrapped in TCA effects

### Core Data Model
```swift
struct ScannedRepository: Equatable {
    var path: String                    // Full path to repository
    var name: String                    // Repository name
    var directory: String               // Parent directory
    var isWorktree: Bool                // Whether it's a git worktree
    var branchName: String?             // Current branch
    var isMergeInProgress: Bool         // Merge status
    var unstagedChangesCount: Int       // Unstaged file count
    var stagedChangesCount: Int         // Staged file count
}
```

### Service Architecture
Services are protocol-based and injected via Dependencies:
- **GitService**: Core Git operations (branch detection, status)
- **XcodeService**: Xcode project detection and opening
- **YouTrackService**: Ticket tracking integration
- **LastOpenedDirectoryService**: Recent directory persistence

## Common Tasks

### Adding a New Button/Action
1. Create new reducer and view files in `RepositoryRow/Buttons/`
2. Conform to TCA pattern: `Reducer`, `State`, `Action`
3. Add to RepositoryRowView's button stack
4. Implement async action handling in reducer using `Effect`

### Implementing New Git Detection
1. Add new helper in `Helpers/` (e.g., `GitXDetector.swift`)
2. Create a detection function that shells out to `git` commands
3. Integrate into `GitService.swift`
4. Update `ScannedRepository` model if new data needed
5. Update UI to display new information

### Adding Service Integration
1. Define protocol in `ServiceProtocols.swift`
2. Implement protocol in `Services/`
3. Add to `Dependencies.swift` injection setup
4. Use in reducers via dependency access

## Important Files and Their Roles

| File | Purpose |
|------|---------|
| `BridgeCommanderApp.swift` | Window configuration, main store setup |
| `TCAModels.swift` | Core data structures |
| `ServiceProtocols.swift` | All service interfaces |
| `Dependencies.swift` | Dependency injection container |
| `RepositoryListReducer.swift` | Main app state and scanning logic |
| `RepositoryRowReducer.swift` | Individual repo actions and state |
| `GitService.swift` | All Git command execution |

## Common Patterns

### Button Components

The app provides two reusable button components:

#### ActionButton
Simple icon-only button for compact actions (copy, delete, etc.):
```swift
ActionButton(
    icon: "trash",
    tooltip: "Remove worktree",
    color: .red,  // Optional custom color (defaults to .secondary)
    action: { store.send(.showConfirmation) }
)
```

#### ToolButton
Labeled button with icon for primary tool actions (Terminal, Xcode, etc.):
```swift
ToolButton(
    label: "Terminal",
    icon: .systemImage("terminal"),
    tooltip: "Open terminal at repository location",
    isProcessing: false,
    tint: .blue,
    action: { store.send(.openTerminalButtonTapped) }
)
```

### Running Shell Commands
Most Git operations use `Process` to execute shell commands:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["-c", "git -C \(path) branch --show-current"]
// Execute and read output...
```

### Effect-Based Async Operations
TCA effects handle async work:
```swift
Effect { send in
    // Perform async work
    send(.resultAction(result))
}
```

### UI State Management
- Each view has corresponding reducer
- State changes flow through reducers
- Views observe store and re-render on state changes

## Testing and Building

### Building
```bash
# Using Xcode
open BridgeCommander.xcodeproj

# Building from command line
xcodebuild -project BridgeCommander.xcodeproj -scheme BridgeCommander build
```

### Running
```bash
# From Xcode (⌘R)
# Or from command line
open -a BridgeCommander
```

## Dependencies

### External Frameworks
- **ComposableArchitecture**: State management library
- **SwiftUI**: UI framework (included with Swift 5.9+)

### System Frameworks Used
- Foundation
- ProcessInfo
- FileManager
- AppleScript (via Process for Terminal automation)

## Known Limitations and Considerations

1. **Terminal Automation**: Requires user permission to control Terminal.app
2. **Git Detection**: Relies on `git` being available in PATH
3. **Worktrees**: Git worktree detection looks for `.git` files with gitdir pointers
4. **Performance**: Large directory scans may take time; consider lazy loading for very large repos
5. **Xcode Projects**: Detection is basic (looks for `.xcodeproj` directories)

## Debugging Tips

### Checking Git Command Issues
- Many operations shell out to git; verify `git` is in PATH
- Check exact git command being run in helpers
- Use verbose logging in Process execution

### State Management Issues
- TCA uses value semantics; verify all state mutations are explicit
- Check reducer actions are properly dispatched
- Use Xcode debugger with breakpoints in reducers

### UI Rendering Problems
- SwiftUI uses reference equality for state; verify StateObject setup
- Check environment objects are properly injected
- Verify @Published properties trigger updates correctly

## Future Enhancement Areas

- Implement repository caching for faster loading
- Add git stash/pop UI actions
- Enhance Xcode project generation
- Add GitHub/GitLab integration
- Implement repository favorites/pinning
- Add search and filtering UI
- Support for multiple scan locations
- Keyboard shortcuts for common actions
