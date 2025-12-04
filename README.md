# Bridge Commander

A macOS application for managing Git repositories and worktrees, built with SwiftUI and the Composable Architecture (TCA). Bridge Commander provides a powerful interface for discovering, monitoring, and interacting with Git repositories across your system.

## Features

### Repository Management
- **Smart Scanning**: Recursively scan directories for Git repositories
- **Worktree Support**: Detect both standard repositories and git worktrees
- **Branch Detection**: Display current branch for each repository
- **Status Monitoring**: Track staged and unstaged changes in real-time
- **Merge Detection**: Identify repositories with merge-in-progress status

### Git Operations
- **Pull**: Pull latest changes from remote with one click
- **Merge Master**: Merge main/master branch into current branch
- **Create Worktree**: Create new git worktrees from any branch
- **Delete Worktree**: Remove worktrees safely
- **Push Changes**: Push commits to remote repository
- **Abort Merge**: Cancel merge operations in progress

### IDE & Tool Integration
- **Terminal**: Open repositories in Terminal.app
- **Xcode**: Detect and open Xcode projects, generate projects from Swift packages
- **Android Studio**: Detect and open Android/Gradle projects
- **Claude Code**: Launch Claude Code CLI in repository context
- **Finder**: Quick access to repository location
- **YouTrack**: Integration with YouTrack ticket tracking

### UI Features
- **Copy Paths**: Copy repository paths to clipboard
- **Share**: Export repository information
- **Progress Indicators**: Visual feedback for long-running operations
- **Settings**: Customize directory, YouTrack configuration, and text abbreviation modes

## Requirements

- macOS 13.0 or later
- Xcode 26.0 or later (for building)
- Git installed and available in PATH

## Building and Running

### Using Xcode

1. Open the project:
   ```bash
   open BridgeCommander.xcodeproj
   ```

2. Build and run (⌘R)

### Building from Command Line

```bash
xcodebuild -project BridgeCommander.xcodeproj -scheme BridgeCommander build
```

### Creating an Archive

To create a release archive for distribution:

```bash
xcodebuild -project BridgeCommander.xcodeproj \
  -scheme BridgeCommander \
  -configuration Release \
  clean archive \
  -archivePath ./build/BridgeCommander.xcarchive
```

The archive will be created at `./build/BridgeCommander.xcarchive`

## Architecture

Bridge Commander uses the **Composable Architecture (TCA)** for state management, providing:
- Predictable state changes through reducers
- Testable business logic
- Effect-based async operations
- Dependency injection for services

### Key Technologies
- **SwiftUI**: Modern declarative UI framework
- **TCA**: State management and architecture pattern
- **Protocol-based Services**: Clean separation of concerns
- **Swift Concurrency**: Async/await for modern async operations

## How It Works

1. **Directory Selection**: Select a directory to scan via Settings or the scan button
2. **Automatic Scanning**: The app recursively discovers all Git repositories, detecting:
   - Standard repos (directories with a `.git` folder)
   - Worktrees (directories with a `.git` file containing a gitdir pointer)
   - Current branch name
   - Staged and unstaged changes
   - Merge status
3. **Repository List**: All repositories are displayed with:
   - Repository name and location
   - Current branch (if detected)
   - Change indicators (staged/unstaged counts)
   - Merge-in-progress status
4. **Actions**: Perform operations on any repository:
   - Git operations (pull, merge, push, create/delete worktrees)
   - Open in IDEs (Xcode, Android Studio, Claude Code)
   - Open in Terminal or Finder
   - Copy paths, view tickets, share information

## Permissions

The app requires the following permissions:
- **File System Access**: To scan directories for repositories
- **Terminal.app Automation**: To open repositories in Terminal (you'll be prompted on first use)
- **Network Access**: For YouTrack integration (if configured)

## Configuration

Access Settings (⌘,) to configure:
- **Refresh interval**: The interval for automatic repositories refresh
- **YouTrack Settings**: Base URL, token, and project IDs for ticket integration

## License

MIT
