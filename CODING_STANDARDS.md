# Coding standards

The checklist a diff is reviewed against before its pull request is opened. The `reviewer`
agent (`.claude/agents/reviewer.md`) applies it; a person can too. Each rule says what to look
for, why it matters, and where the full explanation lives. Mechanical rules are enforced by
the build and `make check`: warnings are errors, imports are explicit, the TCA deprecation
traits are on in every package, `scripts/check-packages.sh` checks the package setup and
`scripts/check-docs.py` that every name the docs mention still exists. What is here is the
judgement those cannot make.

## Architecture and packages

- **A reducer reaches the outside world only through a `@DependencyClient`.** Git, processes,
  the network, the file system and AppKit services are closures on a client with a
  `liveValue` and a `testValue`, never a helper called from the reducer body, so a `TestStore`
  can run it. A new client follows `XcodeService.swift`; CLAUDE.md, "Common Tasks".
- **A lower package does not gain a dependency on a feature package.** TerminalFeature knows
  nothing of Settings or SimulatorFeature (fonts arrive as `NSFont`, colours as `NSColor`, the
  MCP environment as a closure), AppUI nothing of GitCore (`DiffModelMapping` is where they
  meet), GitGraphFeature nothing of Settings, Settings nothing of Sparkle, ActivityLog nothing
  at all. A new import in a `Package.swift` that points up the graph is a finding: pass the
  value or a closure down instead. Each package's README names its own seam.
- **New row status goes on `GitPorcelainStatus` and `RepositoryRowReducer.State`, not on
  `ScannedRepository`**, which holds only what a scan finds.
  [`Packages/GitCore/README.md`](Packages/GitCore/README.md), "Status model".
- **There is one main window.** No second `WindowGroup`, no `Window` in place of it, and the
  main one keeps its `"main"` id: every window builds its own stores, so a second one means a
  second scan, a second restore of every terminal tab and notification clicks reaching only
  one of them. [`BridgeCommander/README.md`](BridgeCommander/README.md), "Main window".

## Effects and state

- **An effect whose answer can be superseded has a cancel id with `cancelInFlight`, and its
  answer names what it asked about.** The answer is dropped when the row, branch, ticket or
  repository has moved on. Both halves are needed: the id alone lets an older answer land
  after a newer one, the key alone misses a fetch still in flight when a rescan changes the
  row without fetching. Every load of the same state, whatever starts it, goes through one
  helper under one id (`loadChanges(state:)`). PRs #139, #141, #153 and #155 each fixed one
  of these. [`Packages/RepositoryFeature/README.md`](Packages/RepositoryFeature/README.md).
- **A check that depends on an input is reset *and* cancelled when that input changes.**
  Resetting alone re-enables the button while the old run lands its verdict under the new
  value. [`Packages/Settings/README.md`](Packages/Settings/README.md), "Accounts".
- **State meant for after an action completes is stored by its completion action**, not when
  it is sent, so a refresh answering in between cannot use it up (`PendingSelection`).
  [`Packages/StagingFeature/README.md`](Packages/StagingFeature/README.md).
- **Work that must outlive a panel runs in a store that outlives it.** `ifLet` cancels a
  child's effects when the child goes `nil`: a Tuist generate running in a toolbar copy was
  SIGTERMed when the terminal panel hid. Views that show a row's state elsewhere scope the
  row's own store rather than holding a copy, and take scoped stores, never row values:
  `IdentifiedArray` observation compares ids only, so a value freezes.
  [`Packages/RepositoryFeature/README.md`](Packages/RepositoryFeature/README.md).
- **Shared mutable state outside a reducer is claimed under its lock**, and a stream that keeps
  only the newest value yields under the lock that read it. Checking and then acting raced in
  `SimulatorMCPServer.startIfNeeded` and the recorder's device stream.
  [`Packages/SimulatorFeature/README.md`](Packages/SimulatorFeature/README.md).
- **The main thread and the cooperative pool never wait on disk or a process.** Logging, file
  writes and process launches go to their own queue or task (the activity log's serial
  queue), except where a write must land before the process exits.
  [`Packages/ActivityLog/README.md`](Packages/ActivityLog/README.md).

## Views

- **Text scales**: `.scaledFont(...)` instead of `.font(...)`, `.scaledBordered` /
  `.scaledBorderedProminent` / `.scaledAutomatic` on text buttons. A literal font size is
  only for a glyph in a fixed frame. [`Packages/AppUI/README.md`](Packages/AppUI/README.md).
- **Menu items show their icons on macOS 27**: `.labelStyle(.titleAndIcon)` on a SwiftUI
  `Menu`'s content and again on every nested `Menu`; `preferredImageVisibility = .visible`
  on an `NSMenuItem`. CLAUDE.md, "Patterns".
- **Anything added to a repository row is paid for on every scroll.** The list builds a fresh
  hosting view for each row that scrolls in (~20 ms a row, measured). A menu in the row is an
  AppUI `PopUpMenuButton`, not a SwiftUI `Menu`; a row does no work in its body and sends
  `onAppear` only while not loaded. A new row control comes with a check that scrolling did
  not get worse. [`Packages/RepositoryFeature/README.md`](Packages/RepositoryFeature/README.md),
  "Scrolling cost".
- **A long or growing list is a `List`, not a `ScrollView` + `LazyVStack`.** The lazy stack
  hung the staging sheet for minutes and pinned headers re-render on every scroll step. In
  such a list: one list-level `.contextMenu(forSelectionType:)`, never one per row (⌘A builds
  every row's menu), and no `.listRowBackground` in the diff viewer.
  [`Packages/AppUI/README.md`](Packages/AppUI/README.md),
  [`Packages/GitGraphFeature/README.md`](Packages/GitGraphFeature/README.md).
- **Each alert or dialog state has exactly one presenter.** `ViewThatFits` builds every
  variant, so it never wraps a view that presents something (`RowActionsLayout` is a
  `Layout` for this); a view mounted twice (the list under the terminal overlay) turns its
  copy off with `presentsButtonAlerts`.
  [`Packages/RepositoryFeature/README.md`](Packages/RepositoryFeature/README.md).
- **A keyboard shortcut is registered unconditionally and decides at press time.** On macOS 27
  a conditionally inserted shortcut can stop being delivered.
  [`Packages/TerminalFeature/README.md`](Packages/TerminalFeature/README.md), "Find".
- **An action that fails or does nothing says so.** A failed fetch shows in the toolbar
  (#51), a rotation the app refuses gets a notice, a link that resolves to nothing beeps.
  A control that silently does nothing reads as broken.

## Processes, git and files

- **Git runs through `ProcessRunner.runGit`, other commands through `ProcessRunner.run`.** A
  git command launched another way (inside a `/bin/sh` script) records itself in the activity
  log, as GitCore's worktree helpers do. A read-only status call passes
  `--no-optional-locks`, or its index write wakes the watcher and every refresh schedules the
  next. [`Packages/ProcessExecution/README.md`](Packages/ProcessExecution/README.md),
  [`Packages/GitCore/README.md`](Packages/GitCore/README.md).
- **Every exit path releases its descriptors.** A GUI app gets 256; a leaked pipe per failed
  launch exhausted them and every later launch failed until a restart. A directory walk keeps
  its open descriptors at the tree's depth.
  [`Packages/ProcessExecution/README.md`](Packages/ProcessExecution/README.md).
- **A new git reader holds for the awkward repositories**: a detached HEAD (scan and status
  must agree, or the row flips on every refresh), a rebase in progress, a linked worktree
  whose `gitdir:` is relative, a branch without an upstream, a repository without a remote,
  and a reftable repository that never writes `refs/`.
  [`Packages/GitCore/README.md`](Packages/GitCore/README.md).
- **Paths are compared canonically.** git reports realpaths, the app builds paths with
  symlinks in them, and FSEvents keeps `/private/var`: a path used as a key goes through
  `realpath` (`pendingWorktreeLaunches`, the watcher).
- **A git write that fails leaves the repository as it found it**, or reports the state it
  left as an outcome the UI offers to finish (conflicts, with Abort or Resolve Later). A
  sequencer must not be left in progress by an error.
  [`Packages/GitCore/README.md`](Packages/GitCore/README.md), `GitCommitActionHelper`.
- **A destructive action names exactly what it removes, checks it again when it acts, and
  asks first.** DerivedData cleanup once matched sibling worktrees' folders by a shared name
  prefix, and `deleteFolders(of:)` classifies afresh rather than trusting an earlier
  measurement. `erase_device` takes no default device.
  [`Packages/ToolsIntegration/README.md`](Packages/ToolsIntegration/README.md).
- **Text typed into a shell is quoted for it**, line breaks flattened, and anything taken from
  a file before being typed is validated to its expected shape (`ClaudeCommand.make(prompt:)`;
  a restored Claude session id is accepted only as a UUID).
  [`Packages/RepositoryFeature/README.md`](Packages/RepositoryFeature/README.md).

## Terminals

- **A terminal session ends through `TerminalViewStore.killSession` or
  `killSessions(notIn:)`**, which send SIGHUP. Dropping the pane leaves the PTY open, and
  SwiftTerm's `terminate()` sends SIGTERM, which interactive zsh ignores.
  [`Packages/TerminalFeature/README.md`](Packages/TerminalFeature/README.md).
- **A pane is resized or re-fonted only when something actually changed, and only the visible
  one.** Each resize is a reflow plus a SIGWINCH, and repeated reflows garble Claude Code's
  screen. Settings applied in `updateNSView` compare before assigning.
  [`Packages/TerminalFeature/README.md`](Packages/TerminalFeature/README.md).
- **What a pane's shell starts with is fixed at its start**: environment, startup command,
  status detection mode. A change to one of them applies to new panes, and the diff says so.

## Network, logging and secrets

- **Requests go through `URLSession.loggedData(for:)`, and a client whose errors matter wraps
  its live closures in `ActivityLog.shared.recordingErrors`.** Missing configuration and
  cancellation are not recorded: they would add an entry per row per refresh.
  [`Packages/ActivityLog/README.md`](Packages/ActivityLog/README.md).
- **Nothing secret reaches the activity log or an error message**: no request headers or
  bodies, no tokens in URLs, the home folder written as `~`. The log is attached to bug
  reports.
- **A response that is not the expected shape throws**, rather than reading as "none". A 200
  with a null repository is `.unauthenticated`; a wrong YouTrack base URL answers with a web
  page. [`Packages/GitHosting/README.md`](Packages/GitHosting/README.md).

## Settings and persistence

- **A new setting is a `@Shared` key in its package's `SharedKeys.swift`**, and a value read
  back from user defaults is validated on read as well as on write: a font size is clamped, a
  font name that no longer resolves falls back, a layout drops items it does not know.
  [`Packages/Settings/README.md`](Packages/Settings/README.md).
- **A replaced setting keeps reading its old key**, so an existing choice carries over
  (`defaultWorktreeSource`, `TerminalThemeSelection`'s raw values).
- **A write that must survive a quit is synchronous.** `@Shared(.fileStorage)` delays writes
  made within a second of the last on a timer that never fires at quit
  (`TerminalTabArchiveClient`). Writes due at quit also run on
  `NSApplication.willTerminateNotification`, since quitting never takes the window off screen.
- **Anything per-app is keyed by `Bundle.main.bundleIdentifier`**, never a literal: the Debug
  build has its own identifier so it keeps its own Application Support, defaults and MCP port.
- **A value that must be stable across launches is not `hashValue`**, which Swift seeds per
  process (`colorIndex` is FNV-1a).

## Private API

- **Simulator behaviour is looked up in idb and AXe before it is reverse-engineered.**
  [`Packages/SimulatorFeature/README.md`](Packages/SimulatorFeature/README.md), "Research
  order".
- **An Objective-C call through `ObjCRuntime` matches its return type**: `ObjCRuntime.object`
  only for methods that return an object, `ObjCRuntime.send` for `void` ones (retaining a
  garbage return register crashed the app). A call that can raise goes through
  `ObjCRuntime.catchingException`: an `NSException` through Swift frames aborts the app.

## Docs, tests and verification

- **A change to how something works updates its package's README in the same diff.** A
  non-obvious decision is recorded there with its reason and, for a measurement or a fact
  about the OS or a framework, what was checked and when ("checked on macOS 27.0.1",
  "measured 2026-10-11"). CLAUDE.md stays project-wide and within its line budget.
- **Logic is tested with Swift Testing where it is pure**; code that shells out to git is
  tested against a real temporary repository where the README says so
  (`GitWorktreeCreatorBaseTests`), otherwise verified by a manual run that the PR describes.
- **The diff passed `make check`**, which builds the app and tests the changed packages and
  their dependents. A build of the app alone does not compile test targets.
- **The public repository names no employer, client or internal project.** Sample data,
  comments, tests and READMEs use generic names (`MyApp.app`, `yt.example`); #177 removed
  one that had slipped in.
- **The live app is not driven blind.** Before automating the release app's UI, back up its
  Application Support folder: a click by element index once hit "Clear results" and wiped the
  tracked repositories. Prefer the Debug build.
