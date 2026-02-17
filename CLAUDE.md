# Bridge Commander - Claude Code Guide

macOS app for managing Git repositories and worktrees. Built with SwiftUI + TCA (Composable Architecture).

## Tech Stack
- Swift 6.0+
- SwiftUI
- Composable Architecture (TCA)
- macOS 26.0+
- Xcode 26.2+

## Project Structure

**Key Directories:**
- `Models/` - TCAModels.swift (ScannedRepository), XcodeProjectState
- `Services/` - GitService, XcodeService, YouTrackService, Dependencies (DI)
- `RepositoriesList/` - Main list View/Reducer
- `RepositoryDetail/` - File staging View/Reducer
- `RepositoryRow/` - Row View/Reducer + Buttons/ (Terminal, Xcode, Git actions, etc.)
- `Helpers/` - Git detectors/helpers, launchers (Terminal, Android Studio, Claude Code)
- `Components/` - ActionButton, ToolButton, GitOperationProgressView
- `Settings/` - SettingsView, AppSettings

## Architecture

**TCA Pattern:**
- Reducers handle state + side effects
- States are immutable
- Actions trigger changes
- Effects wrap async work

**Core Model (ScannedRepository):**
- path, name, directory
- isWorktree, branchName, isMergeInProgress
- unstagedChangesCount, stagedChangesCount

**Services (protocol-based, DI):**
- GitService (git ops)
- XcodeService
- YouTrackService
- LastOpenedDirectoryService

## Common Tasks

**New Button:**
- Create View/Reducer in `RepositoryRow/Buttons/`
- Follow TCA pattern
- Add to RepositoryRowView
- Handle async with Effect

**New Git Detection:**
- Add helper in `Helpers/` (shell out to git)
- Integrate in GitService
- Update ScannedRepository model if needed

**New Service:**
- Define protocol in ServiceProtocols.swift
- Implement in `Services/`
- Add to Dependencies.swift
- Use via @Dependency

**Key Files:**
- BridgeCommanderApp (entry point)
- TCAModels (data)
- GitService (git ops)
- RepositoryListReducer (main state)
- RepositoryRowReducer (row actions)

## Patterns

**Shell Commands:**
- Use `ProcessRunner.runGit()` for git operations
- Or `Process` with `/bin/bash`

**Async:**
- Wrap in TCA `Effect { send in ... }`
- Send result actions

**State:**
- View has Reducer
- State flows through reducers
- Views observe store

## Build & Run

**Build:**
- `open BridgeCommander.xcodeproj`
- Or: `xcodebuild -project BridgeCommander.xcodeproj -scheme BridgeCommander build`

**Run:**
- ⌘R in Xcode
- Or: `open -a BridgeCommander`

## Dependencies

**External:**
- ComposableArchitecture
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
- Git operations use ProcessRunner or Process to shell out to git commands
