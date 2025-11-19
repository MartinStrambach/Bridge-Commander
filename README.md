# Bridge Commander

A macOS application for managing Git repositories and worktrees, built entirely in SwiftUI.

## Features

- Scan directories recursively for Git repositories
- Detect both standard repositories and git worktrees
- Display all discovered repositories in a clean list
- Open any repository in Terminal with one click
- Copy repository paths to clipboard
- Open repositories in Finder

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later

## Building and Running

### Option 1: Using Xcode

1. Open the project in Xcode:
   ```bash
   open bridge_commander
   ```

2. Create a new macOS App project in Xcode:
   - File → New → Project
   - Choose "macOS" → "App"
   - Product Name: "BridgeCommander"
   - Interface: SwiftUI
   - Language: Swift

3. Replace the default files with the files from this directory

4. Build and run (⌘R)

### Option 2: Create Xcode Project from Files

You can create an Xcode project and add all the source files:

1. Open Xcode
2. Create a new macOS App project
3. Add all `.swift` files to the project
4. Build and run

### Option 3: Using Swift Package Manager

While this package includes a Package.swift, note that SPM cannot build standalone macOS GUI applications. You'll need to use Xcode to create a proper .app bundle.

## Project Structure

```
bridge_commander/
├── BridgeCommanderApp.swift       # App entry point
├── Models/
│   └── Repository.swift           # Repository data model
├── ViewModels/
│   └── RepositoryScanner.swift    # Scanning logic and state
├── Views/
│   ├── ContentView.swift          # Main view
│   └── RepositoryRowView.swift    # Repository row component
└── Helpers/
    ├── GitDetector.swift          # Git detection logic
    └── TerminalLauncher.swift     # Terminal launcher
```

## How It Works

1. **Directory Selection**: Click "Select Directory" to choose a folder to scan
2. **Scanning**: The app recursively scans for Git repositories, detecting both:
   - Standard repos (directories with a `.git` folder)
   - Worktrees (directories with a `.git` file containing a gitdir pointer)
3. **Display**: All repositories are listed with their name, path, and type
4. **Actions**: Each repository can be:
   - Opened in Terminal
   - Opened in Finder
   - Path copied to clipboard

## Permissions

The app requires permission to control Terminal.app. You'll be prompted to grant this permission when you first open a repository in Terminal.

## License

MIT
