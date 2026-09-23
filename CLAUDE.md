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
BridgeCommander/          # App entry point (BridgeCommanderApp.swift)
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

### Package Details

**GitCore** — git primitives and data model
- `ScannedRepository` — core model (path, name, branch, worktree flags, change counts)
- `GitService` — main git client (DI-injected as `GitClient`)
- `GitStatusDetector` — `getBranchAndChanges` returns all status in one git call
- `GitStagingClient` / `GitStagingHelper` — staging operations
- `GitCommitDiffClient` / `GitCommitDiffHelper` — read-only: what a single commit changed (`git show`). Merges are diffed against the first parent (`--first-parent`), because git prints no diff for a merge otherwise; a root commit shows every file as an addition. Nothing here writes, so browsing commits never moves HEAD, the index or the working tree
- `GitDiffHunkParser` — shared unified-diff → `DiffHunk` parsing (line numbering + `InlineDiffHighlighter`), used by both the staging and commit diff paths
- `ProcessRunner` — shells out to git via `runGit()`
- Helpers: `GitWorktreeScanner`, `GitWorktreeCreator`, `GitBranchNameSanitizer` (whitespace → underscores for typed branch names), `GitWorktreeRemover`, `GitMergeDetector`, `GitBranchDetector`, `GitDefaultBranchDetector`, `GitBranchListHelper`, `GitPullHelper`, `GitPushHelper`, `GitFetchHelper`, `GitMergeHelper`, `GitCheckoutHelper`, `GitAbortMergeHelper`, `GitStashHelper`
- `GitImageDiffLoader` / `ImageDiffSides` / `ImageFileDetector` — load both versions of a changed image (`git cat-file blob`) so a diff view can render them instead of a binary placeholder. `ImageDiffSource.revision(revision:path:)` is the general side (`<rev>:<path>`); `.head(path:)` is sugar for `HEAD`. `resolve(for:isStaged:)` covers the staging comparisons, `resolve(for:commitHash:)` a commit against its first parent

**AppUI** — shared UI components
- `ActionButton`, `ToolButton`, `HeaderButton`, `HunkActionButton`
- `DiffViewer`, `DiffLineView`, `HunkCard` (`HunkHeaderView`, `HunkFooterView`, `hunkCardRow()`), `ImageDiffView` — diff display (images render side by side as Before/After)
- `DiffViewer` renders diff lines with a `List`, not a `ScrollView` + `LazyVStack`. A lazy stack reports its content's height as its own ideal height, so a large diff handed the enclosing sheet an ideal size of ~10⁶ pt that changed every time more rows were measured; the sheet re-measured, the stack re-estimated, and the main thread spun in `LazyLayoutViewCache.updateItemPhases` / `LazyStack.measureEstimates` for minutes (hang reports 2026-09-06 and 2026-09-07 — flattening the stack in v0.6.7 did not help, the signature was identical). `List` is `NSTableView`-backed: rows recycle and its ideal size is 0×0 regardless of row count
- Hunk header, lines and footer are emitted as sibling rows of one `List`, deliberately not as a `Section` — a plain-style `List` pins section headers, which would make hunk headers sticky. Rows need `.listRowInsets(EdgeInsets())` and `.listRowSeparator(.hidden)` (see `diffListRow()`), plus `defaultMinListRowHeight` of 1 so content height wins and no gap opens in the card's side borders. Do not add `.listRowBackground` — it costs ~40% of scroll time and changes nothing visually
- `DiffViewer` has two inits: the staging one takes the hunk stage/unstage/discard closures, `init(diff:)` is read-only and renders hunk headers without action buttons. `FileChangeRow` likewise has `init(file:)` for a row with no staging checkbox
- `GitOperationProgressView`, `BannerView`, `EmptyStateView`, `ScrollableErrorAlertView`
- `FileChangeRow`, `SectionHeader`, `RepositoryIcon`
- The **`DiffModelMapping`** target (same package, separate product) holds the `GitCore.*.toAppUI()` conversions. It is where AppUI and GitCore meet, so the `AppUI` target itself stays free of any git dependency and the mapping is not duplicated per feature. Import it alongside `AppUI` wherever a GitCore diff is rendered

**Settings**
- `SettingsReducer` + `SettingsView`
- `AppSettings` keys via `SharedKeys`
- `PeriodicRefreshInterval`, `TerminalColorTheme`, `TerminalOpeningBehavior`, `TuistCacheType`, `RepoGroupSettings`
- `TerminalFontSize` — the built-in terminal's point size (8–32, default 13 = `NSFont.systemFontSize`, which is what SwiftTerm's `FontSet.defaultFont` asks for, so an untouched install renders as it did before the setting existed). Stored as a bare `Double` and clamped on every write, including the one that comes back from user defaults: SwiftTerm divides the pane width by the cell width to get its column count, so a zero or negative size is not a value it can survive. Written by the Settings stepper and by ⌘+/⌘−/⌘0 (`TerminalLayoutReducer`'s zoom actions)
- `TerminalFontFamily` — the built-in terminal's typeface, stored as the bare font name `NSFont(name:size:)` takes, with `""` meaning `NSFont.monospacedSystemFont` (what SwiftTerm used before the setting existed, and the only way to say "follow the system" — the system monospaced face has no stable public name). `resolve(name:size:)` falls back to that face for any name that no longer resolves, since the name comes from user defaults and a font can be uninstalled. The picker lists only families with a fixed-pitch member (`availableMonospacedFamilies()`): a proportional face turns SwiftTerm's character grid ragged. `TerminalPanelView` resolves name + size into one `NSFont` and hands it to `TerminalContainerRepresentable`, so TerminalFeature needs no Settings dependency
- `TerminalProfileImporter` / `TerminalProfile` / `TerminalProfileImportClient` — import Terminal.app color profiles, either from an exported `.terminal` file or from Terminal's own settings in one tap. Both sources are property lists holding the same profile dictionaries; the colors in them are **`NSKeyedArchiver`-encoded `NSColor` objects**, not hex strings, so each one is `NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self,…)` then `usingColorSpace(.sRGB)`. Converting first is not optional: Apple's bundled profiles store colors in Generic RGB *and* Generic Gray, and reading `redComponent` off a gray color raises. Alpha is dropped (the "Clear" profiles are 0.85–0.95 translucent; SwiftTerm's color type has no alpha). Reading Terminal's settings goes through `UserDefaults.persistentDomain(forName: "com.apple.Terminal")` — it sees unflushed values, and works only because the app is unsandboxed
- Only 2 of Terminal's 12 bundled profiles define ANSI colors at all ("Basic", "Pro" and most others set just a text and background color), so `TerminalProfile.ansi` is optional rather than defaulted — `nil` means "keep SwiftTerm's default palette", which *is* Terminal's. A palette is all sixteen or none: SwiftTerm ignores any array that is not exactly 16 long, so a partial one would silently leave the previous theme's colors installed
- A profile's `Font` key is an encoded `NSFont` and is imported too, into `TerminalProfile.font` (name + size), applied to the global font settings when that profile is picked as the theme (`SettingsReducer.adoptProfileFont`) — font is part of a profile in Terminal.app, so a theme switch overwrites a hand-picked font the same way it overwrites the colors. It must **not** be decoded with `unarchivedObject(ofClass: NSFont.self,…)` the way the colors are: when the archived face is not installed AppKit substitutes one and the name is lost, and Terminal's own profiles name `SFMonoTerminal-Regular`, which ships *inside* Terminal.app and is not registered system-wide — so unarchiving it yields `.AppleSystemUIFont`, a proportional face, and the import silently records the wrong font. `TerminalProfileImporter.font(from:)` instead maps the archived class name `NSFont` onto the decode-only `ArchivedFont` stub (`setClass(_:forClassName:)`) and reads `NSName`/`NSSize` as written, with `decodingFailurePolicy = .setErrorAndReturn` so a non-font value under that key returns nil rather than raising. Applying is split accordingly: the size always applies, the family only when `NSFont(name:size:)` resolves it, and the import alert names any profile whose font it could not load
- An imported profile's `CursorColor` and `SelectionColor` ride along in `ResolvedTerminalTheme` (`nil` for built-in themes and for profiles that omit them, meaning "keep SwiftTerm's default") and are assigned in `TerminalViewStore.view` after `installColors`, onto `caretColor` and `selectedTextBackgroundColor`. Setting the selection background **must** set `selectedTextForegroundColor` with it: SwiftTerm does not tint the selection, it replaces the foreground of every selected cell with that color, which defaults to black — readable against its own teal default and invisible against the dark selection colors most Terminal profiles ship. It is set to the profile's own text color, the color whose author already judged the selection color to work behind it
- `TerminalThemeSelection` — `.builtIn` or `.imported`. A built-in case's raw value is the bare `TerminalColorTheme` raw value, unprefixed, so the setting this type replaced migrates itself: an existing `"dracula"` in user defaults still reads back as `.builtIn(.dracula)`. `resolve(profiles:)` falls back to the default theme when a selection names a deleted profile

**ToolsIntegration** — external tool services
- `ServiceProtocols` — protocol definitions
- `XcodeService`, `YouTrackService`, `LastOpenedDirectoryService`
- `TerminalLauncher`, `ClaudeCodeLauncher`, `AndroidStudioLauncher`
- `XcodeProjectDetector`, `XcodeProjectGenerator`, `XcodeDerivedDataHelper`
- `TuistCommandHelper`, `BranchNameFormatter`, `FileOpener`, `PermissionChecker`
- Terminal.app opens a window at the user's home directory the moment it launches, and a plain `do script` (no target) always makes *another* window — so launching it cold left two windows behind, one at home. `TerminalLauncher.openSystemTerminal` therefore reuses that startup window (`do script … in front window`) when Terminal was not already running, for both the new-window and new-tab behaviors. Terminal's dictionary cannot make a tab (`make new tab` fails with -10000), so a new tab means posting ⌘T — and it must be posted **in-process with `CGEvent`**, not handed to `osascript`. macOS checks the Accessibility grant of whoever posts the event, so an `osascript` child gets checked against `osascript`, which has no grant of its own: it fails with `osascript is not allowed to send keystrokes (-1002)` no matter what the user granted the app, which is why tabs silently came out as windows. `requestNewTerminalTab` gates on `PermissionChecker.isAccessibilityPermitted()` (the app's own grant, what `RepositoryListView`'s Accessibility banner tracks) and posts the event itself
- Because the keystroke is in-process, opening a tab is three steps rather than one script: `prepareScript` activates Terminal and returns the front tab's `tty` (or `""` when it already finished the job), then ⌘T is posted, then `newTabScript` polls until the front window's selected tab is no longer that `tty` and runs the command there. Poll rather than guessing a delay — Terminal reports the new tab asynchronously, and a fixed delay lands the command in the tab that was already there. Both builders are `internal` so the script text is unit-tested. If the keystroke cannot be posted, or the tab never arrives, fall back to a plain `do script`: a window beats opening nothing and beats typing into a tab that may have something running in it

**YouTrackMenu** — YouTrack ticket menu
- `YouTrackButtonReducer` / `YouTrackButtonView` — moves a ticket to a different state
- Offers only the transitions YouTrack reports as reachable (`IssueDetails.stateTransitions`); the row supplies them, this package only applies the chosen one

**TerminalFeature** — embedded terminal panel
- `TerminalSession`, `TerminalViewStore`, `TerminalViewRepresentable`, `TerminalStatusDotView`
- `TerminalPaletteMapping` — `[NSColor]` → `[SwiftTerm.Color]` for `installColors`. The palette crosses the package boundary as `NSColor`, not as a Settings type, so TerminalFeature stays free of a Settings dependency (the same split the fg/bg colors already use); RepositoryFeature resolves the theme and passes the result down. SwiftTerm has no support for reading any theme file format — `Color.parse` handles X11 specs (`#rrggbb`, `rgb:r/g/b`) only, so the plist decoding lives in Settings. `installColors` derives all 256 colors from the 16 plus the terminal's background and foreground, so it must run *after* `nativeForegroundColor`/`nativeBackgroundColor` are set
- Killing a session must go through `TerminalViewStore.killSession` / `killSessions(notIn:)`, which hang up the shell with SIGHUP. Dropping the pane alone does not close the PTY (SwiftTerm leaves a read pending), and SwiftTerm's `terminate()` sends SIGTERM, which interactive zsh ignores. `RepositoryListView` calls `killSessions(notIn:)` whenever the session ids in state change, so reducer-side removals (worktree deletion) hang up too.
- `allowMouseReporting` is driven by the `terminalMouseReporting` setting (default on) and assigned in `TerminalViewRepresentable.updateNSView`, not at creation, so panes pick up a change to the setting. Forcing it off breaks more than clicks: SwiftTerm's `scrollWheel` checks the flag *before* `terminal.mouseMode`, so a TUI on the alternate screen (lazygit, vim) gets the wheel as bare Up/Down arrow keys, which carry no coordinates — scrolling then always moves the focused pane instead of the one under the pointer. Text selection does not need the flag off; ⇧-drag bypasses reporting (`shiftBypassesMouseReporting`)
- `ClaudeAwareTerminalView` re-snaps the cell grid on `viewDidChangeBackingProperties` / `viewDidMoveToWindow` when the window's backing scale differs from the one the grid was measured for, by reassigning `font` (the only public entry to SwiftTerm's `resetFont`). SwiftTerm snaps cell width/height to the pixel grid of the screen current when the font is set and never re-measures on a screen change, so moving the window from an external monitor to the MacBook display (different scale) drew a stale grid: smeared glyphs, cell edges between pixels, wrong column count. Guarded on an actual scale change because the reassignment resizes the PTY (SIGWINCH) and clears the selection
- ⌥←/⌥→ word motion is sent by `ClaudeAwareTerminalView` itself (a local `keyDown` monitor + `OptionArrowWordMotion`), because panes run with `optionAsMetaKey = false` (so Czech Option+4 = `$` works) and in that mode SwiftTerm drops it: legacy input becomes `moveWordLeft:`, which its `doCommand` doesn't handle (bash got nothing), and under the kitty protocol it sends a bare arrow with Option removed (Claude Code moved one character). Sends `ESC b`/`ESC f` normally and `CSI 1;3D`/`CSI 1;3C` when kitty flags are active. A monitor because SwiftTerm's `keyDown` is `public`, not `open`
- The global `terminalStartupCommand` setting (Settings → Terminal), or a repository group's own `RepoGroupSettings.terminalStartupCommand` when that is non-blank (a blank group command means "use the global one", not "none" — for "none", the group sets `skipGlobalTerminalStartupCommand`), rides on `TerminalSession.startupCommand` (trimmed, `nil` when blank) into every built-in tab the group opens — first open, new tab, retry. `ClaudeAwareTerminalView` types it (plus `\r`) on the shell's **first output**, not right after `startProcess`: bytes written before the line editor is up are echoed by the tty as typeahead and then again at the prompt, so the command showed twice. It is typed, not passed as `zsh -c`, so it runs in the user's interactive shell, lands in history, and the shell stays open after it. External terminals (Terminal.app, iTerm, Warp) do not get it
- The font arrives already resolved (an `NSFont`, not a name and a size) and is assigned in the same place, but **only when the font name or point size actually differs** — compared field by field rather than with `!=`, which also weighs matrix and descriptor attributes the view may have derived — unlike the flags beside it. SwiftTerm's `font` setter rebuilds the bold/italic faces, calls `selectNone()`, and re-derives cols/rows from the new cell size in `resetFont()` — which resizes the PTY and SIGWINCHes the shell. That is correct for a deliberate zoom and wrong on every unrelated update pass, which is why the assignment is guarded

**StagingFeature** — file staging panel
- `RepositoryDetail` (reducer) / `RepositoryDetailView` — the staging panel; the public entry point presented by RepositoryFeature
- `FileChangeListReducer` / `FileChangeListView` — staged/unstaged file lists
- `FileDiffViewerReducer` / `FileDiffViewerView` — diff pane with hunk stage/unstage/discard
- `CommitReducer` / `CommitView` — commit sheet
- `MergeStatusReducer` / `MergeStatusBannerView` — merge-in-progress banner
- Display models come from the `DiffModelMapping` target in the AppUI package (`import DiffModelMapping`)

**GitGraphFeature** — commit graph
- `GitGraphReducer` / `GitGraphView` — the commit table (`GitGraphLayout` assigns lanes, `GitGraphColumnWidths` persists column widths)
- `CommitDetailReducer` / `CommitDetailView` — the bottom pane: the selected commit's changed files on the left, the selected file's diff on the right, in a read-only `DiffViewer`
- The commit table is a `List(selection:)` (not a `ScrollView` + `LazyVStack`), so selection and ↑/↓ keyboard navigation are native; the list takes focus on open. Rows need `.listRowInsets(EdgeInsets())`, `.listRowSeparator(.hidden)` and `defaultMinListRowHeight = GitGraphRowView.rowHeight` to stay flush — any inter-row gap breaks the vertical lane lines. The "Load More" row is `.selectionDisabled()` so arrow keys skip it, and the column header stays a `Section` header *inside* the list so it keeps the rows' insets
- Use one list-level `.contextMenu(forSelectionType:)`, never per-row `.contextMenu` — ⌘A would make AppKit build every row's menu (the same O(rows²) freeze documented in `FileChangeListView`)
- The selection binding ignores nil writes: the list emits one when it cannot carry selection across a wholesale row replacement, and a background refresh must not close the diff pane
- `selectedCommitHash` is kept on the parent state alongside `commitDetail` on purpose, so a row observes only that one property instead of re-rendering whenever the child loads a file list or diff
- `commitTapped` builds the child state and sends `.commitDetail(.task)` itself rather than relying on the view's `.task`, so re-selecting always reloads even when SwiftUI reuses the pane
- Selection is read-only: it shells out to `git show` only, and never checks anything out
- Keyboard focus between the commit list and the file list is an explicit `@FocusState` (`GitGraphPane`), not left to clicks: with a plain `Bool` the commit list kept focus after a file was clicked, so ↑/↓ kept walking the commits. Clicking a row moves focus to its list via a `.simultaneousGesture(TapGesture())` on the row, not via the file selection binding — the list also writes its selection back on reload (moving focus on those writes stole it from the commit list after every ↑/↓), and a click on the already-selected first file changes no selection at all; selecting a commit (click or key) moves it back to the commit list — the file list is swapped for a spinner while the new commit loads, so leaving focus there left ↑/↓ reaching nothing; → (commit list, with the pane open) and ← (file list) switch between them

**RepositoryFeature** — top-level feature UI and reducers
- `RepositoryListReducer` / `RepositoryListView` — main list state
- `RepositoryRowReducer` / `RepositoryRowView` — per-row state and actions
- `RepoGroupReducer` / `RepoGroupView` — grouped repo display
- Per-button Reducer+View pairs: `CreateWorktreeButton`, `DeleteWorktreeButton`, `TerminalButton`, `ClaudeCodeButton`, `XcodeProjectButton`, `TuistButton`, `TicketButton`, `ShareButton`, `WebButton`
- `TerminalLayoutReducer` / `TerminalLayoutView` / `TerminalPanelView`
- Two drag-to-reorder helpers, both `onDrag`/`onDrop` with a `public.text` payload for reasons documented in `ReorderableDrag.swift` (a `Section` header cannot be a `draggable` source, an undeclared UTType never matches a drop). `View.reorderable(payload:isEnabled:isTargeted:insertionEdge:onDrop:)` moves on release and draws an insertion line; the sidebar's repository group headers use it because sections under a `List` cannot slide. `View.liveReorderable(id:isEnabled:draggedId:onMove:)` (`LiveReorderableDrag.swift`) moves the dragged item on `dropEntered`, so the row animates around the pointer during the drag like browser tabs; the terminal tab pills use it. The dragged id lives in a `@State` shared by the row because a drop delegate cannot read the pasteboard synchronously. Reducers treat what arrives as untrusted: `repositoryGroupDropped` ignores a path that names no group, `terminalLayout(.moveTab)` ignores a session id that names no tab or a tab of another repository. Both apply the same rule, the dragged item takes the target's place, and `moveTab` applies it inside `withAnimation`
- `ExternalWorktreeCreator` — worktree creation with no dialog, for the App Intent. `plan(...)` is the pure, tested decision (a name that already exists as a branch is checked out instead of failing; otherwise the base is the requested one, else `DefaultBranchResolver.resolveBaseBranch` as the dialog pre-selects it); `create(...)` reads `worktreeBasePath`/`groupSettings` through `@SharedReader`, runs `GitWorktreeCreator` + `WorktreeFileCopier`, then posts `.worktreeCreatedExternally` with the tracked root path. `RepositoryListView` turns that notification into `.view(.worktreeCreatedExternally(rootPath:))`, which rescans that group (ignored for a path that names no group) — the root store is private to `RootRepositoryView`, so a notification is the only way in
- The terminal overlay takes **scoped stores**, never row values: `TerminalLayoutView.repositoryGroups` is `[StoreOf<RepoGroupReducer>]` and `activeRowStore` is resolved in `RepositoryListView`. TCA's `IdentifiedArray` observation compares element ids only, so a row handed over as a value freezes its counts at whenever the overlay last rebuilt — that was the stale push status in terminal view (2026-09-07). Store collections are wrapped in `Array(...)` because the sidebar is a `LazyVStack`

**App Intents (Siri / Apple Intelligence / Shortcuts / Spotlight)** — in the app target, `BridgeCommander/AppIntents/`
- `CreateWorktreeIntent` (repository, branch name, optional base branch; returns the worktree path) calls `ExternalWorktreeCreator.create`
- `RepositoryEntity` — id is the tracked root path; `RepositoryEntityQuery` reads `@SharedReader(.trackedRepoPaths)`, so it lists exactly what the sidebar shows
- `RepositoryEntity` is an `IndexedEntity`: `RepositoryIndexer.reindex(paths:)` replaces everything in Spotlight with the tracked list (delete-then-add — the index cannot be read back, and an untracked repository must stop being offered to Siri). Run from the same `BridgeCommanderApp` task as `updateAppShortcutParameters()`; failures are only logged, since the intents work without the index. On macOS 27 `RepositoryEntityQuery` also conforms to `IndexedEntityQuery` (availability-gated extension; the target still deploys to 26), so the system can ask for a rebuild itself
- `BridgeCommanderShortcuts` — the `AppShortcutsProvider`. Phrases that name a repository need `updateAppShortcutParameters()`, which `BridgeCommanderApp` calls whenever `trackedRepoPaths` changes
- Intents stay in the app target: metadata extraction there needs no `AppIntentsPackage` wiring

## Architecture

**TCA Pattern:**
- Reducers handle state + side effects
- States are immutable
- Actions trigger changes
- Effects wrap async work

**Core Model (ScannedRepository) — in GitCore:**
- path, name, directory
- isWorktree, branchName, isMergeInProgress
- unstagedChangesCount, stagedChangesCount, unpushedCount, behindCount, hasRemoteBranch

**Git status is fetched in one call:**
- `GitStatusDetector.getBranchAndChanges` runs `git status --porcelain=v2 --branch` and parses everything (branch, staged/unstaged counts, unpushed, behind, remote branch)
- `RepositoryRowReducer.fetchAll` fires 1 git process per row

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
