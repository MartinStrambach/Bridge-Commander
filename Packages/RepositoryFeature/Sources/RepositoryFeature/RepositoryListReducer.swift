import ActionButtons
import ActivityLog
import AppKit
import ComposableArchitecture
import Foundation
import GitActionsMenu
import GitCore
import GitGraphFeature
internal import OrderedCollections
import Settings
import SimulatorFeature
import TerminalFeature
import ToolsIntegration

enum SortMode: String, Equatable {
	case state = "State"
	case ticket = "Ticket"
	case branch = "Branch"
}

@Reducer
struct RepositoryListReducer {
	@ObservableState
	struct State: Equatable {
		fileprivate(set) var repositoryGroups: IdentifiedArrayOf<RepoGroupReducer.State> = []
		fileprivate(set) var isScanning = false
		fileprivate(set) var sortMode: SortMode = .state

		/// Hides rows without a live terminal session. Deliberately not persisted — like `sortMode`,
		/// it resets to off on every launch.
		fileprivate(set) var showsActiveTerminalsOnly = false

		var searchText: String = ""

		/// The terminal tabs and panes, and whether the panel showing them is on screen. Always
		/// here: hiding the panel keeps them, so it comes back as it was.
		var terminals = TerminalTabs()
		/// The panel's toolbar and sheets, present exactly while `terminals.isPanelVisible`.
		var terminalLayout: TerminalLayoutReducer.State?
		/// Set once the tabs saved by the previous launch have been reopened, so an `onAppear` that
		/// fires again does not reopen them a second time.
		fileprivate var hasRestoredTerminalTabs = false

		/// Worktrees just created with a terminal follow-up, keyed by their symlink-resolved path.
		/// The row does not exist until a scan finds the worktree, so the terminal opens from
		/// `didScanGroup` — whichever scan gets there first — rather than from the creation.
		fileprivate(set) var pendingWorktreeLaunches: [String: WorktreeTerminalLaunch] = [:]

		/// The rows the file system watch covers, sorted. A rescan that finds the same rows leaves
		/// the running watch alone instead of restarting it.
		fileprivate(set) var watchedRepositoryPaths: [String] = []

		@Shared(.trackedRepoPaths)
		fileprivate(set) var trackedRepoPaths: [String] = []

		@Shared(.collapsedRepoPaths)
		fileprivate(set) var collapsedRepoPaths: [String] = []

		@Shared(.periodicRefreshInterval)
		fileprivate(set) var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Shared(.groupSettings)
		fileprivate(set) var groupSettings: [String: RepoGroupSettings] = [:]

		@Shared(.terminalStartupCommand)
		fileprivate(set) var terminalStartupCommand = ""

		@Shared(.terminalStartupCommandInNewTabs)
		fileprivate(set) var terminalStartupCommandInNewTabs = false

		@Shared(.terminalNotifications)
		fileprivate(set) var terminalNotifications = true

		@Presents
		var alert: AlertState<Action.Alert>?

		fileprivate var isSystemEventsPermissionGranted: Bool?
		fileprivate var isPermissionWarningDismissed = false
		/// Guards against a second osascript probe while one is still running: launch triggers
		/// both `onAppear` and `didBecomeActive`, and the probe is far too expensive to run twice.
		fileprivate var isSystemEventsProbeInFlight = false

		fileprivate var isAccessibilityPermissionGranted: Bool?
		fileprivate var isAccessibilityPermissionWarningDismissed = false

		var showPermissionDialog: Bool {
			isSystemEventsPermissionGranted == false && !isPermissionWarningDismissed
		}

		var showAccessibilityPermissionDialog: Bool {
			isAccessibilityPermissionGranted == false && !isAccessibilityPermissionWarningDismissed
		}
	}

	/// What started a refresh of every row; the activity log says which.
	enum RefreshTrigger: Equatable {
		/// The refresh button or ⌘R.
		case user
		/// The periodic refresh, at the interval Settings sets.
		case periodic(PeriodicRefreshInterval)

		var activityLogDescription: String {
			switch self {
			case .user:
				"requested by the user"
			case let .periodic(interval):
				"automatic, every \(interval.displayName)"
			}
		}
	}

	enum Action: ViewAction {
		case view(ViewAction)
		case addRepository(String)
		case addRepositoryFailed(String)
		case addRepositorySucceeded(rootPath: String, scanned: [ScannedRepository])
		case alert(PresentationAction<Alert>)
		case checkAccessibilityPermission
		case checkPermissions
		case checkSystemEventsPermission
		/// A file ⌘-clicked in a terminal could not be opened.
		case terminalFileOpenFailed(String)
		/// A terminal tab's notification was clicked.
		case terminalNotificationTapped(sessionId: UUID)
		/// A simulator MCP tool call touched a device.
		case simulatorActivityReported(SimulatorActivity)
		case didReceiveSystemEventsPermission(Bool)
		case didScanGroup(rootPath: String, rows: [ScannedRepository])
		case refreshRepositories(RefreshTrigger)
		/// Rows' repositories changed on disk; see `GitRepositoryWatcherClient`.
		case repositoriesChangedOnDisk([GitRepositoryChange])
		/// Reopens the tabs saved when the window last closed. Once per launch.
		case restoreTerminalTabs
		case repositoryGroups(IdentifiedActionOf<RepoGroupReducer>)
		case scanCompleted
		case scanFailed
		case performDebouncedSort
		case startPeriodicRefresh
		case startScan
		case stopPeriodicRefresh
		case terminalLayout(TerminalLayoutReducer.Action)
		case terminals(TerminalWorkspaceReducer.Action)

		enum ViewAction {
			case activeTerminalFilterChanged(Bool)
			case clearButtonTapped
			case addRepository(String)
			case didBecomeActive
			case dismissAccessibilityPermissionWarningButtonTapped
			case dismissPermissionWarningButtonTapped
			case groupSettingsChanged
			case onAppear
			case onDisappear
			case openAccessibilitySettingsButtonTapped
			case openAutomationSettingsButtonTapped
			case openHomeTerminalButtonTapped
			case periodicRefreshIntervalChanged
			case refreshButtonTapped
			case repositoryGroupDropped(draggedPath: String, ontoPath: String)
			/// The window is closing or the app is quitting: the tabs open now are the ones the next
			/// launch reopens. `panes` is what each pane is doing: its shell's directory, and the
			/// Claude conversation in it.
			case saveTerminalTabsRequested
			/// ⌘F while the terminal panel is on screen.
			case terminalFindRequested
			case searchTextChanged(String)
			case showTerminalsRequested
			case sortModeButtonTapped
			case terminalSessionStatusChanged(sessionId: UUID, status: TerminalSessionStatus)
			/// A ⌘-clicked link in a pane named a file.
			case terminalFileLinkClicked(sessionId: UUID, link: TerminalFileLink)
			/// The program in a pane asked for a notification (OSC 9 / OSC 777).
			case terminalNotificationReceived(sessionId: UUID, notification: TerminalNotification)
		}

		enum Alert: Equatable {
			case dismiss
			case closeLastTabConfirmed(sessionId: UUID)
			case quitAppConfirmed
		}
	}

	/// The ⌘W-on-the-last-tab question. Built here rather than inline so the test that pins it
	/// asserts against the same value the reducer stores.
	static func lastTabAlert(sessionId: UUID, otherRepoCount: Int) -> AlertState<Action.Alert> {
		AlertState {
			TextState("Close Bridge Commander?")
		} actions: {
			ButtonState(role: .destructive, action: .quitAppConfirmed) {
				TextState("Quit Bridge Commander")
			}
			ButtonState(action: .closeLastTabConfirmed(sessionId: sessionId)) {
				TextState("Close Tab Only")
			}
			ButtonState(role: .cancel, action: .dismiss) {
				TextState("Cancel")
			}
		} message: {
			TextState(
				"""
				This is the last terminal tab for this repository, but \
				\(otherRepoCount) other \
				\(otherRepoCount == 1 ? "repository has" : "repositories have") terminals running.
				"""
			)
		}
	}

	private nonisolated enum CancellableId: Hashable {
		case terminalNotificationTaps
		case simulatorActivity
		case periodicRefresh
		case repositoryWatch
		case scan
		case sortAfterFetch
	}

	@Dependency(LastOpenedDirectoryClient.self)
	private var lastOpenedDirectoryClient

	@Dependency(TerminalNotificationClient.self)
	private var terminalNotificationClient

	@Dependency(TerminalTabArchiveClient.self)
	private var terminalTabArchiveClient

	@Dependency(GitRepositoryWatcherClient.self)
	private var gitRepositoryWatcherClient

	@Dependency(SimulatorClient.self)
	private var simulatorClient

	@Dependency(TerminalPanesClient.self)
	private var terminalPanes

	var body: some Reducer<State, Action> {
		CombineReducers {
			Scope(\.terminals, action: \.terminals) {
				TerminalWorkspaceReducer()
			}
			core
			// The toolbar's state exists exactly while the panel is on screen, whichever action
			// showed or hid it. Before the `ifLet` below, which cancels the toolbar's effects when
			// it sees the state go.
			Reduce { state, _ in
				if !state.terminals.isPanelVisible {
					state.terminalLayout = nil
				}
				else if state.terminalLayout == nil {
					state.terminalLayout = TerminalLayoutReducer.State()
				}
				return .none
			}
		}
		.ifLet(\.terminalLayout, action: \.terminalLayout) {
			TerminalLayoutReducer()
		}
		// The one place shells are hung up: a session that left the state, whichever way it left —
		// its tab closed, its repository's tabs closed, its worktree deleted, a run tab or a
		// failed one replaced.
		.onChange(of: { $0.terminals.sessions.ids }) { [terminalPanes] oldIds, state in
			let closed = Array(oldIds.subtracting(state.terminals.sessions.ids))
			guard !closed.isEmpty else {
				return .none
			}

			return .run { _ in
				await terminalPanes.kill(closed)
			}
		}
	}

	private var core: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			// MARK: - View Actions

			case let .view(.terminalSessionStatusChanged(sessionId, status)):
				// Reported by the pane itself, and kept on the session list rather than on the
				// terminal panel: the panel can be closed while a session keeps running, and the
				// dots in the repository list still have to move. A late report from a session
				// that has already been killed finds no entry and changes nothing.
				guard let session = state.terminals.sessions[id: sessionId] else {
					return .none
				}

				state.terminals.sessions[id: sessionId]?.status = status
				// A new repository's tab usually starts Claude itself, and Claude reaching its prompt
				// a few seconds later is the tab being ready, not waiting on an answer — by then the
				// user has often moved on to open the next one.
				if session.awaitsStartupPrompt, status == .waitingForInput {
					state.terminals.sessions[id: sessionId]?.awaitsStartupPrompt = false
					return .none
				}
				return claudeNotificationEffect(for: session, changingTo: status, in: state)

			case let .view(.terminalNotificationReceived(sessionId, notification)):
				// The pane already holds itself at waiting until the user types; this is the
				// session learning it, and the reason the status-change path posts nothing more.
				guard let session = state.terminals.sessions[id: sessionId] else {
					return .none
				}

				state.terminals.sessions[id: sessionId]?.status = .waitingForInput
				state.terminals.sessions[id: sessionId]?.awaitsStartupPrompt = false
				let location = notificationLocation(for: session, in: state)
				let title = notification.title ?? location
				return postNotification(
					TerminalNotificationContent(
						sessionId: sessionId,
						title: title,
						subtitle: title == location ? nil : location,
						body: notification.body
					),
					for: session,
					in: state
				)

			case let .view(.terminalFileLinkClicked(sessionId, link)):
				// Opened the way the staging panel's "Open in IDE" opens a file, with the tab's own
				// repository's Xcode project, even for a file outside it.
				guard let repositoryPath = state.terminals.sessions[id: sessionId]?.repositoryPath else {
					return .none
				}

				let iosSubfolderPath = findRowState(for: repositoryPath, in: state)?.iosSubfolderPath ?? ""
				return .run { send in
					do {
						let xcodeProjectPath = XcodeProjectDetector.findXcodeProject(
							in: repositoryPath,
							iosSubfolderPath: iosSubfolderPath
						)
						try await FileOpener.openFileInIDE(
							atPath: link.path,
							line: link.line,
							repositoryPath: repositoryPath,
							xcodeProjectPath: xcodeProjectPath
						)
					}
					catch {
						await send(.terminalFileOpenFailed(error.localizedDescription))
					}
				}

			case let .terminalFileOpenFailed(message):
				state.alert = AlertState {
					TextState("Failed to Open File")
				} message: {
					TextState(message)
				}
				return .none

			case .view(.onAppear):
				return .merge(
					.send(.restoreTerminalTabs),
					.send(.startScan),
					.send(.startPeriodicRefresh),
					.send(.checkPermissions),
					.run { [terminalNotificationClient] send in
						for await sessionId in terminalNotificationClient.taps() {
							await send(.terminalNotificationTapped(sessionId: sessionId))
						}
					}
					.cancellable(id: CancellableId.terminalNotificationTaps, cancelInFlight: true),
					.run { [simulatorClient] send in
						for await activity in simulatorClient.activity() {
							await send(.simulatorActivityReported(activity))
						}
					}
					.cancellable(id: CancellableId.simulatorActivity, cancelInFlight: true)
				)

			case let .simulatorActivityReported(activity):
				// The pane comes up beside the terminal Claude is working in — the repository of the
				// calling session, or the one on screen for a `claude` outside the app. A call from a
				// repository the user is not looking at opens that repository's pane without pulling
				// the panel over to it; it is there when the user switches.
				guard state.terminalLayout != nil else {
					return .none
				}
				let repositoryPath: String?
				if let sessionId = activity.terminalSessionId {
					repositoryPath = state.terminals.sessions[id: sessionId]?.repositoryPath
				}
				else {
					repositoryPath = state.terminals.activeRepositoryPath
				}
				guard let repositoryPath else {
					return .none
				}
				return .send(.terminalLayout(.simulatorPane(.activityReported(
					deviceId: activity.deviceId,
					repositoryPath: repositoryPath
				))))

			case let .terminalNotificationTapped(sessionId):
				// The tab may have been closed since the notification went out; the app still
				// comes forward, it just opens on nothing new.
				if let session = state.terminals.sessions[id: sessionId] {
					state.terminals.show(session)
					state.terminals.showPanel()
				}
				return .run { [terminalNotificationClient] _ in
					await terminalNotificationClient.activateApp()
				}

			case .restoreTerminalTabs:
				guard !state.hasRestoredTerminalTabs else {
					return .none
				}

				state.hasRestoredTerminalTabs = true
				if let saved = terminalTabArchiveClient.load() {
					restoreTerminalTabs(saved, in: &state)
				}
				return .none

			case .view(.didBecomeActive):
				return .send(.checkPermissions)

			case .view(.terminalFindRequested):
				return .send(.terminals(.findRequested(.show)))

			case .view(.saveTerminalTabsRequested):
				// Written here and now, not from an effect: this arrives as the app quits, and an
				// effect's task would not get to run before the process exits.
				terminalTabArchiveClient.save(SavedTerminalTabs(state.terminals, panes: terminalPanes.snapshots()))
				return .none

			case .stopPeriodicRefresh:
				return .cancel(id: CancellableId.periodicRefresh)

			case .view(.onDisappear):
				// The window is closing. Its tabs are saved and their shells hung up now, both
				// before returning: the panes belong to the app, not to the window's views, so
				// nothing else would end them, and an effect might not get to run. The next window
				// reopens the saved tabs, as a launch does.
				terminalTabArchiveClient.save(SavedTerminalTabs(state.terminals, panes: terminalPanes.snapshots()))
				terminalPanes.killAll()
				state.terminals = TerminalTabs()
				state.hasRestoredTerminalTabs = false
				// Forgotten too, so the scan after the next `onAppear` starts the watch again.
				state.watchedRepositoryPaths = []
				return .merge(
					.cancel(id: CancellableId.periodicRefresh),
					.cancel(id: CancellableId.repositoryWatch)
				)

			case .view(.periodicRefreshIntervalChanged):
				return .run { send in
					await send(.stopPeriodicRefresh)
					await send(.startPeriodicRefresh)
				}

			case .view(.groupSettingsChanged):
				for (groupId, settings) in state.groupSettings {
					guard state.repositoryGroups[id: groupId] != nil else {
						continue
					}

					state.repositoryGroups[id: groupId]?.settings = settings
					if var header = state.repositoryGroups[id: groupId]?.header {
						applySettings(settings, to: &header)
						state.repositoryGroups[id: groupId]?.header = header
					}
					let worktreeIds = state.repositoryGroups[id: groupId]?.worktrees.ids ?? []
					for wtId in worktreeIds {
						if var worktree = state.repositoryGroups[id: groupId]?.worktrees[id: wtId] {
							applySettings(settings, to: &worktree)
							state.repositoryGroups[id: groupId]?.worktrees[id: wtId] = worktree
						}
					}
				}
				return .none

			case .view(.sortModeButtonTapped):
				switch state.sortMode {
				case .state: state.sortMode = .ticket
				case .ticket: state.sortMode = .branch
				case .branch: state.sortMode = .state
				}
				sortGroupsInState(in: &state)
				return .none

			case let .view(.activeTerminalFilterChanged(isOn)):
				state.showsActiveTerminalsOnly = isOn
				return .none

			case let .view(.repositoryGroupDropped(draggedPath, ontoPath)):
				// Only whole repositories move; worktrees inside a group stay under `sortMode`.
				// The dragged repo takes the target's place, pushing the target out of the way —
				// dropping on the row above moves up, on the row below moves down.
				guard
					draggedPath != ontoPath,
					let from = state.repositoryGroups.index(id: draggedPath),
					let to = state.repositoryGroups.index(id: ontoPath)
				else {
					return .none
				}

				var groups = Array(state.repositoryGroups)
				let moved = groups.remove(at: from)
				groups.insert(moved, at: to)
				state.repositoryGroups = IdentifiedArrayOf(uniqueElements: groups)
				persistGroupOrder(in: &state)
				return .none

			case let .view(.searchTextChanged(text)):
				state.searchText = text
				return .none

			case .view(.clearButtonTapped):
				state.repositoryGroups.removeAll()
				state.$trackedRepoPaths.withLock { $0.removeAll() }
				state.$collapsedRepoPaths.withLock { $0.removeAll() }
				state.isScanning = false
				state.watchedRepositoryPaths = []
				return .merge(
					.cancel(id: CancellableId.periodicRefresh),
					.cancel(id: CancellableId.repositoryWatch)
				)

			case let .view(.addRepository(path)):
				return .send(.addRepository(path))

			case .view(.openAutomationSettingsButtonTapped):
				return .run { _ in
					if
						let url = URL(
							string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
						)
					{
						NSWorkspace.shared.open(url)
					}
				}

			case .view(.openAccessibilitySettingsButtonTapped):
				return .run { _ in
					if
						let url = URL(
							string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
						)
					{
						NSWorkspace.shared.open(url)
					}
				}

			case .view(.dismissPermissionWarningButtonTapped):
				state.isPermissionWarningDismissed = true
				return .none

			case .view(.dismissAccessibilityPermissionWarningButtonTapped):
				state.isAccessibilityPermissionWarningDismissed = true
				return .none

			case .view(.refreshButtonTapped):
				return .send(.refreshRepositories(.user))

			case .view(.openHomeTerminalButtonTapped):
				return openTerminal(for: NSHomeDirectory(), in: &state)

			case .view(.showTerminalsRequested):
				guard !state.terminals.isPanelVisible else {
					return .none
				}

				// Back as it was hidden. A panel that has shown nothing yet (tabs restored from a
				// launch with it closed) opens on the terminal the user was in most recently,
				// preferring a live one over a lingering failed tab.
				if state.terminals.panes.isEmpty {
					let sessions = state.terminals.sessions
					let live = sessions.filter(\.status.isLive)
					guard
						let session = state.terminals.mostRecent(among: live)
							?? live.first
							?? state.terminals.mostRecent(among: sessions)
							?? sessions.first
					else {
						return .none
					}

					state.terminals.show(session)
				}
				state.terminals.showPanel()
				return .none

			// MARK: - Add Repository

			case let .addRepository(path):
				let normalized = normalizePath(path)
				guard !state.trackedRepoPaths.contains(normalized) else {
					return .none
				}

				state.isScanning = true
				return .run { [normalized] send in
					let rows = await GitWorktreeScanner.listWorktrees(forRepo: normalized)
					if rows.isEmpty {
						await send(.addRepositoryFailed(normalized))
					}
					else {
						await send(.addRepositorySucceeded(rootPath: normalized, scanned: rows))
					}
				}
				.cancellable(id: CancellableId.scan)

			case let .addRepositoryFailed(path):
				state.isScanning = false
				let name = URL(fileURLWithPath: path).lastPathComponent
				state.alert = AlertState {
					TextState("Not a Valid Git Repository")
				} message: {
					TextState("'\(name)' does not appear to be a Git repository.")
				}
				return .none

			case let .addRepositorySucceeded(rootPath, scanned):
				state.isScanning = false
				state.$trackedRepoPaths.withLock { $0.append(rootPath) }
				if
					let group = buildGroup(
						rootPath: rootPath,
						scanned: scanned,
						collapsedPaths: Set(state.collapsedRepoPaths),
						sortMode: state.sortMode,
						groupSettings: state.groupSettings
					)
				{
					state.repositoryGroups.append(group)
					sortGroupsByTrackedOrder(in: &state)
				}
				return watchRepositories(in: &state)

			// MARK: - Full Scan (all tracked repos)

			case .startScan:
				// Don't interrupt an in-flight scan — let it complete.
				// A concurrent second scan would cancel the first mid-flight via cancelInFlight:true,
				// leaving some repos' groups never added. The cancelled scan also orphans git processes
				// (withCheckedContinuation can't be cancelled), which compete with the new scan.
				guard !state.isScanning else {
					return .none
				}

				// Migration: on first launch, import the legacy single-repo path.
				if state.trackedRepoPaths.isEmpty {
					let legacy = lastOpenedDirectoryClient.load() ?? ""
					if !legacy.isEmpty {
						state.$trackedRepoPaths.withLock { $0 = [normalizePath(legacy)] }
					}
				}
				guard !state.trackedRepoPaths.isEmpty else {
					return .none
				}

				state.isScanning = true
				let paths = Array(state.trackedRepoPaths)
				// Permission checks deliberately don't hang off the scan: refreshRepositories
				// routes through here, so every ⌘R used to re-run them (see .checkPermissions).
				return .merge(
					.run { send in
						await withTaskGroup(of: (String, [ScannedRepository]).self) { group in
							for path in paths {
								group.addTask {
									let rows = await GitWorktreeScanner.listWorktrees(forRepo: path)
									return (path, rows)
								}
							}
							for await (rootPath, rows) in group {
								await send(.didScanGroup(rootPath: rootPath, rows: rows))
							}
						}
						await send(.scanCompleted)
					}
					.cancellable(id: CancellableId.scan, cancelInFlight: true)
				)

			// MARK: - Per-group scan (worktree added/removed)

			case let .repositoryGroups(.element(id: groupId, action: .header(.worktreeCreated(path, launch)))),
			     let .repositoryGroups(.element(id: groupId, action: .worktrees(.element(_, .worktreeCreated(path, launch))))):
				if let launch {
					state.pendingWorktreeLaunches[resolvedPath(path)] = launch
				}
				return rescanGroup(groupId, in: &state)

			case let .repositoryGroups(.element(id: groupId, action: .worktrees(.element(id: worktreePath, .worktreeDeleted)))):
				state.terminals.close(state.terminals.tabs(of: worktreePath).map(\.id))
				return rescanGroup(groupId, in: &state)

			// MARK: - Scan Results

			case let .didScanGroup(rootPath, scanned):
				if state.repositoryGroups[id: rootPath] != nil {
					// Existing group: merge rows, preserving cached PR/ticket data
					mergeGroupRows(into: &state, rootPath: rootPath, scanned: scanned)
					openPendingWorktreeTerminals(inGroup: rootPath, state: &state)
				}
				else if !scanned.isEmpty {
					// New group (e.g., from migration path on first launch)
					if
						let group = buildGroup(
							rootPath: rootPath,
							scanned: scanned,
							collapsedPaths: Set(state.collapsedRepoPaths),
							sortMode: state.sortMode,
							groupSettings: state.groupSettings
						)
					{
						state.repositoryGroups.append(group)
						sortGroupsByTrackedOrder(in: &state)
					}
				}
				return .none

			case .scanCompleted,
			     .scanFailed:
				state.isScanning = false
				return watchRepositories(in: &state)

			case let .repositoriesChangedOnDisk(changes):
				var effects: [EffectOf<RepositoryListReducer>] = []
				var rescannedGroupIds: Set<String> = []
				for change in changes {
					guard let groupId = groupId(containing: change.repositoryPath, in: state) else {
						continue
					}

					// A worktree made or removed outside the app (`git worktree add` in a terminal)
					// gets or loses its row the same way one made from the dialog does.
					if change.kinds.contains(.worktreeList), rescannedGroupIds.insert(groupId).inserted {
						effects.append(rescanGroup(groupId, in: &state))
					}
					let rowKinds = change.kinds.subtracting(.worktreeList)
					if !rowKinds.isEmpty {
						effects.append(sendToRow(.changedOnDisk(rowKinds), for: change.repositoryPath, in: state))
					}
				}
				return .merge(effects)

			// MARK: - Refresh

			case let .refreshRepositories(trigger):
				guard !state.repositoryGroups.isEmpty else {
					return .none
				}

				// Capture only the ids (Sendable) and rebuild the actions inside the effect.
				let refreshTargets = state.repositoryGroups.map { group in
					(groupId: group.id, worktreeIds: group.worktrees.map(\.id))
				}
				let rowCount = refreshTargets.reduce(0) { $0 + 1 + $1.worktreeIds.count }
				// Send the refreshes sequentially instead of merging to stagger row refreshes.
				// Merging all effects at once spawns 7×N git processes simultaneously (thundering herd).
				// Sequencing them means git load ramps up gradually.
				return .run { send in
					ActivityLog.shared.record(
						.refresh,
						"Refresh of \(rowCount) \(rowCount == 1 ? "repository" : "repositories") (\(trigger.activityLogDescription))"
					)
					await send(.startScan)
					for target in refreshTargets {
						await send(.repositoryGroups(.element(id: target.groupId, action: .header(.refresh))))
						for worktreeId in target.worktreeIds {
							await send(.repositoryGroups(.element(
								id: target.groupId,
								action: .worktrees(.element(id: worktreeId, action: .refresh))
							)))
						}
					}
				}

			case .startPeriodicRefresh:
				let interval = state.periodicRefreshInterval
				return .run { send in
					while true {
						try await Task.sleep(nanoseconds: UInt64(interval.timeInterval * 1_000_000_000))
						await send(.refreshRepositories(.periodic(interval)))
					}
				}
				.cancellable(id: CancellableId.periodicRefresh, cancelInFlight: true)

			// MARK: - Terminal

			case let .repositoryGroups(.element(id: groupId, action: .header(.openTerminalForRepo))):
				guard let repositoryPath = state.repositoryGroups[id: groupId]?.header.path else {
					return .none
				}

				return openTerminal(for: repositoryPath, in: &state)

			case let .repositoryGroups(.element(
				id: _,
				action: .worktrees(.element(id: repositoryPath, action: .openTerminalForRepo))
			)):
				return openTerminal(for: repositoryPath, in: &state)

			// MARK: - Collapse Persistence

			case let .repositoryGroups(.element(id: groupId, action: .toggleCollapse)):
				// RepoGroupReducer has already mutated isCollapsed; sync to persisted list.
				if let group = state.repositoryGroups[id: groupId] {
					var collapsed = Set(state.collapsedRepoPaths)
					if group.isCollapsed {
						collapsed.insert(groupId)
					}
					else {
						collapsed.remove(groupId)
					}
					state.$collapsedRepoPaths.withLock { $0 = collapsed.sorted() }
				}
				return .none

			// MARK: - Remove Group

			case let .repositoryGroups(.element(id: groupId, action: .remove)):
				state.repositoryGroups.remove(id: groupId)
				state.$trackedRepoPaths.withLock { $0.removeAll { $0 == groupId } }
				state.$collapsedRepoPaths.withLock { $0.removeAll { $0 == groupId } }
				return watchRepositories(in: &state)

			// MARK: - Re-sort on YouTrack fetch

			case .repositoryGroups(.element(_, .header(.didFetchYouTrack))),
			     .repositoryGroups(.element(_, .worktrees(.element(_, .didFetchYouTrack)))):
				guard state.sortMode == .state else {
					return .none
				}

				@Dependency(\.continuousClock)
				var clock

				// Debounce: many rows fetch in parallel — sort once after the burst settles
				return .run { send in
					try await clock.sleep(for: .milliseconds(300))
					await send(.performDebouncedSort)
				}
				.cancellable(id: CancellableId.sortAfterFetch, cancelInFlight: true)

			case .performDebouncedSort:
				sortGroupsInState(in: &state)
				return .none

			// MARK: - Terminals

			// What a new terminal runs and where it starts comes from the repository's settings,
			// so the workspace asks for the session and places what it is given.
			case let .terminals(.delegate(.sessionRequested(request, placement))):
				let session = switch request {
				case let .firstTab(repositoryPath):
					firstTerminalSession(for: repositoryPath, in: state)
				case let .extraTab(repositoryPath, directory):
					extraTerminalSession(for: repositoryPath, directory: directory, in: state)
				case let .replacement(old):
					replacementTerminalSession(for: old, in: state)
				}
				return .send(.terminals(.sessionBuilt(session, placement)))

			case let .terminals(.delegate(.lastTabCloseRequested(sessionId, otherRepositoryCount))):
				state.alert = Self.lastTabAlert(sessionId: sessionId, otherRepoCount: otherRepositoryCount)
				return .none

			case .terminals:
				return .none

			// MARK: - Terminal Layout

			case let .terminalLayout(.simulatorPane(.delegate(.runRequested(command, title, repositoryPath)))):
				// The simulator pane's Run: into the repository's run tab, replacing what ran there
				// (its shell is hung up with it), so running again is a fresh build and launch with
				// a clean log, as in Xcode.
				// The repository the pane was beside when Run was pressed, which in a split need not
				// be the active one: the pane stays beside the repository that has it open while
				// the keyboard is elsewhere.
				guard let path = repositoryPath ?? state.terminals.activeRepositoryPath else {
					return .none
				}

				let existing = state.terminals.tabs(of: path).first(where: \.isRunTab)
				let session = TerminalSession(
					id: newSessionId(),
					repositoryPath: path,
					startupCommand: command,
					runTitle: title,
					tabIndex: existing?.tabIndex ?? state.terminals.nextTabIndex(for: path)
				)
				// The tab on screen stays on screen: the run is followed in the simulator pane,
				// and switching tabs took the user away from the Claude or shell they were
				// typing in. Only a run tab being replaced while on screen hands its pane to
				// its successor.
				if let existing {
					state.terminals.replace(existing.id, with: session)
				}
				else {
					state.terminals.add(session)
				}
				if state.terminals.activeSessionId == nil {
					state.terminals.show(session)
				}
				return .none

			case let .terminalLayout(.finishMergeCompleted(repositoryPath, error)):
				if let error {
					state.alert = AlertState {
						TextState("Finish Merge Failed")
					} message: {
						TextState(error.localizedDescription)
					}
					return .none
				}
				return refreshRow(for: repositoryPath, in: state)

			case let .terminalLayout(.pushCompleted(_, error)):
				// The toolbar's Push button is the one git operation in the panel that doesn't go
				// through the header's actions menu, so it needs the same completion routing: the
				// unpushed count it renders comes from the row, and nothing else re-reads it.
				if let error {
					state.alert = AlertState {
						TextState("Push Failed")
					} message: {
						TextState(error.localizedDescription)
					}
					return .none
				}
				guard let path = state.terminals.activeRepositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case .terminalLayout(.stagingDetail(.dismiss)):
				// Parity with RepositoryRowReducer.repositoryDetail(.dismiss), which covers the
				// same sheet opened from a row: a commit or push made inside it changes the row's
				// counts, so re-run its status fetch once the sheet closes.
				guard let path = state.terminals.activeRepositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case .terminalLayout(.gitGraph(.presented(.delegate(.repositoryChanged)))):
				// The graph's commit menu checked something out or added a commit: same row
				// refresh as the graph opened from a row gets (RepositoryRowReducer.gitGraph).
				guard let path = state.terminalLayout?.gitGraph?.repositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case let .terminalLayout(.gitGraph(.presented(.delegate(.worktreeCreated(worktreePath))))):
				// Rescan the graph's group, as a worktree created from its rows would.
				guard
					let path = state.terminalLayout?.gitGraph?.repositoryPath,
					let group = state.repositoryGroups.first(where: { $0.header.path == path || $0.worktrees[id: path] != nil })
				else {
					return .none
				}
				return .send(.repositoryGroups(.element(id: group.id, action: .header(.worktreeCreated(path: worktreePath, launch: nil)))))

			case .terminalLayout(.refreshActiveRepoRequested):
				// ⌘R in terminal mode refreshes just the opened repo. The home-directory
				// session has no repo row, so refreshRow falls through to .none there.
				guard
					let path = state.terminals.activeRepositoryPath,
					findRowState(for: path, in: state) != nil
				else {
					return .none
				}
				return .merge(
					.run { _ in
						ActivityLog.shared.record(.refresh, "Refresh of \(path) (requested by the user)")
					},
					refreshRow(for: path, in: state)
				)

			case .terminalLayout:
				return .none

			// MARK: - Permissions

			case .checkPermissions:
				// Both permissions can only be changed outside the app, so launch and
				// re-activation are the only moments worth checking — and then only for what
				// isn't already granted.
				//
				// This used to hang off .startScan with the manual refresh clearing both flags
				// first, which meant every ⌘R re-ran the System Events probe: an osascript
				// process that asks System Events to enumerate every running process, measured at
				// 110-290ms, and which hid the warning banner for as long as it took to answer.
				//
				// A granted permission being revoked mid-session is rare and self-announcing —
				// the terminal action fails while the user is looking right at it — so a granted
				// result is never re-probed.
				return .merge(
					state.isAccessibilityPermissionGranted == true ? .none : .send(.checkAccessibilityPermission),
					state.isSystemEventsPermissionGranted == true ? .none : .send(.checkSystemEventsPermission)
				)

			case .checkAccessibilityPermission:
				// In-process and free, unlike the System Events probe below.
				state.isAccessibilityPermissionGranted = PermissionChecker.isAccessibilityPermitted()
				return .none

			case .checkSystemEventsPermission:
				guard !state.isSystemEventsProbeInFlight else {
					return .none
				}

				state.isSystemEventsProbeInFlight = true
				return .run { send in
					let granted = await PermissionChecker.isSystemEventsAutomationPermitted()
					await send(.didReceiveSystemEventsPermission(granted))
				}

			case let .didReceiveSystemEventsPermission(granted):
				state.isSystemEventsProbeInFlight = false
				state.isSystemEventsPermissionGranted = granted
				return .none

			// MARK: - Alert

			case let .alert(.presented(.closeLastTabConfirmed(sessionId))):
				state.terminals.close([sessionId])
				return .none

			case .alert(.presented(.quitAppConfirmed)):
				// The window closing on the way out hangs the sessions up (`onDisappear`); terminate
				// runs on the main actor because it drives AppKit's own shutdown sequence.
				return .run { _ in
					await MainActor.run {
						NSApplication.shared.terminate(nil)
					}
				}

			case .alert:
				return .none

			// MARK: - Catch-all

			case .repositoryGroups:
				return .none
			}
		}
		.forEach(\.repositoryGroups, action: \.repositoryGroups) {
			RepoGroupReducer()
		}
		.ifLet(\.$alert, action: \.alert)
	}

	/// Points the file system watch at the rows the list has now. Rows update the moment their
	/// repository changes on disk — a checkout in the built-in terminal, an edit, a fetch — so the
	/// periodic refresh is only a fallback. Called after every scan; leaves a running watch alone
	/// when the rows are the same, since restarting it would drop events in between.
	private func watchRepositories(in state: inout State) -> EffectOf<RepositoryListReducer> {
		let paths = state.repositoryGroups
			.flatMap { [$0.header.path] + $0.worktrees.map(\.path) }
			.sorted()
		guard paths != state.watchedRepositoryPaths else {
			return .none
		}

		state.watchedRepositoryPaths = paths
		guard !paths.isEmpty else {
			return .cancel(id: CancellableId.repositoryWatch)
		}

		return .run { [gitRepositoryWatcherClient] send in
			for await changes in gitRepositoryWatcherClient.changes(paths) {
				await send(.repositoriesChangedOnDisk(changes))
			}
		}
		.cancellable(id: CancellableId.repositoryWatch, cancelInFlight: true)
	}

	/// Re-lists one group's worktrees, for a worktree added or removed. The rows are merged, so
	/// their loaded state survives.
	private func rescanGroup(_ groupId: String, in state: inout State) -> EffectOf<RepositoryListReducer> {
		state.isScanning = true
		return .run { send in
			let rows = await GitWorktreeScanner.listWorktrees(forRepo: groupId)
			await send(.didScanGroup(rootPath: groupId, rows: rows))
			await send(.scanCompleted)
		}
		.cancellable(id: CancellableId.scan)
	}

	/// Posts a notification when a session starts waiting at Claude's prompt, and withdraws it once
	/// the session is back at work — by then the user has answered it.
	private func claudeNotificationEffect(
		for session: TerminalSession,
		changingTo status: TerminalSessionStatus,
		in state: State
	) -> Effect<Action> {
		let wasWaiting = session.status == .waitingForInput
		let isWaiting = status == .waitingForInput
		guard wasWaiting != isWaiting else {
			return .none
		}

		let client = terminalNotificationClient
		let sessionId = session.id
		guard isWaiting else {
			return .run { _ in await client.remove(sessionId) }
		}

		return postNotification(
			TerminalNotificationContent(
				sessionId: sessionId,
				title: notificationLocation(for: session, in: state),
				body: "Claude is waiting for your input."
			),
			for: session,
			in: state
		)
	}

	/// Nothing is posted for a terminal on screen while the app is frontmost: the user is already
	/// looking at it, whichever pane has the keyboard.
	private func postNotification(
		_ content: TerminalNotificationContent,
		for session: TerminalSession,
		in state: State
	) -> Effect<Action> {
		guard state.terminalNotifications else {
			return .none
		}

		let client = terminalNotificationClient
		let isOnScreen = state.terminals.isOnScreen(session.id)
		return .run { _ in
			if isOnScreen, await client.isAppActive() {
				return
			}
			await client.post(content)
		}
	}

	/// Names the tab: the repository, and which tab when it has more than one.
	private func notificationLocation(for session: TerminalSession, in state: State) -> String {
		let name = findRowState(for: session.repositoryPath, in: state)?.name
			?? URL(fileURLWithPath: session.repositoryPath).lastPathComponent
		let tabCount = state.terminals.sessions.count { $0.repositoryPath == session.repositoryPath }
		return tabCount > 1 ? "\(name) · Terminal \(session.tabIndex)" : name
	}
}

// MARK: - Private Free Functions

/// Puts the top-level repository groups in the user's manual order, which is `trackedRepoPaths`
/// itself: a repo lands at the end when added and moves only when dragged. Called once whenever a
/// group is added so the list never re-sorts while rendering — a parallel scan reports groups in
/// completion order, which is otherwise arbitrary. A group whose path isn't tracked (it cannot
/// normally happen) sorts last, alphabetically, rather than silently jumping to the front.
private func sortGroupsByTrackedOrder(in state: inout RepositoryListReducer.State) {
	let rank = Dictionary(
		uniqueKeysWithValues: state.trackedRepoPaths.enumerated().map { ($0.element, $0.offset) }
	)
	state.repositoryGroups.sort { lhs, rhs in
		let lhsRank = rank[lhs.id] ?? .max
		let rhsRank = rank[rhs.id] ?? .max
		if lhsRank != rhsRank {
			return lhsRank < rhsRank
		}
		return lhs.header.name.localizedCaseInsensitiveCompare(rhs.header.name) == .orderedAscending
	}
}

/// Writes the on-screen group order back to `trackedRepoPaths`, which is what a relaunch restores
/// from. Tracked paths with no group — one that failed to scan this launch — keep their relative
/// order at the end instead of being dropped from the file.
private func persistGroupOrder(in state: inout RepositoryListReducer.State) {
	let order = state.repositoryGroups.map(\.id)
	let placed = Set(order)
	state.$trackedRepoPaths.withLock { paths in
		paths = order + paths.filter { !placed.contains($0) }
	}
}

private func sortGroupsInState(in state: inout RepositoryListReducer.State) {
	for groupId in state.repositoryGroups.ids {
		guard let group = state.repositoryGroups[id: groupId] else {
			continue
		}

		let sorted = sortRepositories(Array(group.worktrees), sortMode: state.sortMode)
		state.repositoryGroups[id: groupId]?.worktrees = IdentifiedArrayOf(uniqueElements: sorted)
	}
}

private func normalizePath(_ path: String) -> String {
	URL(fileURLWithPath: path).standardizedFileURL.path
}

/// The id of a session a reducer opens, from the `uuid` dependency so a test can name it.
private func newSessionId() -> UUID {
	@Dependency(\.uuid) var uuid
	return uuid()
}

/// A repository's first tab: in its mobile subfolder when it has both platforms, running the
/// group's startup command unless `startupCommandOverride` replaces it.
private func firstTerminalSession(
	for repositoryPath: String,
	startupCommandOverride: String? = nil,
	in state: RepositoryListReducer.State
) -> TerminalSession {
	let repoSettings = groupSettings(for: repositoryPath, in: state)
	let subfolder: String =
		if repoSettings.supportsIOS, repoSettings.supportsAndroid {
			repoSettings.mobileSubfolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		}
		else {
			""
		}
	return TerminalSession(
		id: newSessionId(),
		repositoryPath: repositoryPath,
		startingDirectory: (repositoryPath as NSString).appendingPathComponent(subfolder),
		startupCommand: startupCommandOverride ?? startupCommand(for: repoSettings, in: state)
	)
}

/// A tab beside the ones a repository already has. Only the first tab runs the startup command
/// by default; extra ones are usually wanted as a plain shell beside it.
private func extraTerminalSession(
	for repositoryPath: String,
	directory: String? = nil,
	in state: RepositoryListReducer.State
) -> TerminalSession {
	TerminalSession(
		id: newSessionId(),
		repositoryPath: repositoryPath,
		startingDirectory: directory,
		startupCommand: state.terminalStartupCommandInNewTabs
			? startupCommand(for: groupSettings(for: repositoryPath, in: state), in: state)
			: nil,
		tabIndex: state.terminals.nextTabIndex(for: repositoryPath)
	)
}

/// A fresh session for a tab whose shell failed. It runs the startup command only if the tab it
/// replaces did, so retrying a plain-shell tab does not suddenly start the command in it. A run
/// tab runs its own command again, not the group's.
private func replacementTerminalSession(
	for old: TerminalSession,
	in state: RepositoryListReducer.State
) -> TerminalSession {
	let repositoryPath = old.repositoryPath
	guard !old.isRunTab else {
		return TerminalSession(
			id: newSessionId(),
			repositoryPath: repositoryPath,
			startupCommand: old.startupCommand,
			runTitle: old.runTitle,
			tabIndex: old.tabIndex
		)
	}

	return TerminalSession(
		id: newSessionId(),
		repositoryPath: repositoryPath,
		startupCommand: old.startupCommand == nil
			? nil
			: startupCommand(for: groupSettings(for: repositoryPath, in: state), in: state),
		tabIndex: old.tabIndex
	)
}

/// Reopens the tabs saved by the previous launch, each in the directory its shell was in and
/// resuming the Claude conversation it had, and the panel on the tab that was on screen. When the
/// panel was closed it stays closed, and the tabs' shells start the first time it opens — panes
/// are created by the panel.
private func restoreTerminalTabs(
	_ saved: SavedTerminalTabs,
	in state: inout RepositoryListReducer.State
) {
	guard state.terminals.sessions.isEmpty else {
		return
	}

	var onScreen: TerminalSession?
	var currentTabByRepo: [String: UUID] = [:]
	var paneTabs: [Int: [UUID]] = [:]
	var paneShown: [Int: UUID] = [:]
	for tab in saved.tabs {
		let session = TerminalSession(
			id: newSessionId(),
			repositoryPath: tab.repositoryPath,
			startingDirectory: tab.directory,
			startupCommand: tab.startupCommand,
			resumingClaudeSession: tab.claudeSessionId,
			tabIndex: tab.tabIndex
		)
		state.terminals.add(session)
		if tab.isRepositoryCurrentTab {
			currentTabByRepo[tab.repositoryPath] = session.id
		}
		if tab.isOnScreen {
			onScreen = session
		}
		if let paneIndex = tab.paneIndex {
			paneTabs[paneIndex, default: []].append(session.id)
			// A file written before panes had tabs of their own names one tab per pane.
			if tab.isPaneCurrentTab ?? true {
				paneShown[paneIndex] = session.id
			}
		}
	}

	state.terminals.restoreCurrentTabs(currentTabByRepo)
	guard let onScreen else {
		return
	}

	// The split comes back only whole enough to be one: a pane whose tab on screen was not saved
	// (a run tab, a failed one) is closed up, and what is left must still be several, the
	// terminal with the keyboard among them.
	let split = paneShown.keys.sorted().prefix(TerminalTabs.maxPanes).compactMap { index in
		paneShown[index].map { TerminalPane(shown: $0, tabs: paneTabs[index] ?? [$0]) }
	}
	state.terminals.restorePanel(split: split, showing: onScreen)
}

/// Opens the built-in terminal on every worktree of the group that was created with a terminal
/// follow-up and that the latest scan has now turned into a row.
private func openPendingWorktreeTerminals(
	inGroup groupId: String,
	state: inout RepositoryListReducer.State
) {
	guard !state.pendingWorktreeLaunches.isEmpty, let group = state.repositoryGroups[id: groupId] else {
		return
	}
	for row in group.worktrees {
		guard let launch = state.pendingWorktreeLaunches.removeValue(forKey: resolvedPath(row.path)) else {
			continue
		}
		openTerminal(for: row.path, startupCommandOverride: launch.startupCommandOverride, in: &state)
	}
}

/// The creator builds the worktree path itself, while rows carry the one `git worktree list`
/// reports, which git has run through realpath. Resolving both lets them meet.
private func resolvedPath(_ path: String) -> String {
	URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
}

/// `startupCommandOverride` replaces the group's startup command in a newly created first tab;
/// a repository that already has a tab just gets it shown.
@discardableResult
private func openTerminal(
	for repositoryPath: String,
	startupCommandOverride: String? = nil,
	in state: inout RepositoryListReducer.State
) -> EffectOf<RepositoryListReducer> {
	if let existing = state.terminals.lastActiveSession(for: repositoryPath) {
		state.terminals.show(existing)
	}
	else {
		state.terminals.open(
			firstTerminalSession(for: repositoryPath, startupCommandOverride: startupCommandOverride, in: state)
		)
	}
	state.terminals.showPanel()
	return .none
}

private func buildGroup(
	rootPath: String,
	scanned: [ScannedRepository],
	collapsedPaths: Set<String>,
	sortMode: SortMode,
	groupSettings: [String: RepoGroupSettings]
) -> RepoGroupReducer.State? {
	let isCollapsed = collapsedPaths.contains(rootPath)
	let settings = groupSettings[rootPath] ?? RepoGroupSettings()
	let effectiveMobileSubfolder = (settings.supportsIOS && settings.supportsAndroid)
		? settings.mobileSubfolderPath
		: ""
	let allRows = scanned.map { repo in
		RepositoryRowReducer.State(
			path: repo.path,
			name: repo.name,
			branchName: repo.branchName,
			isWorktree: repo.isWorktree,
			supportsIOS: settings.supportsIOS,
			supportsAndroid: settings.supportsAndroid,
			mobileSubfolderPath: effectiveMobileSubfolder,
			iosSubfolderPath: settings.iosSubfolderPath,
			supportsTuist: settings.supportsTuist,
			ticketIdRegex: settings.ticketIdRegex,
			xcodeFilePreference: settings.xcodeFilePreference,
			supportsWeb: settings.supportsWeb,
			webIndexPath: settings.webIndexPath,
			defaultBranch: settings.defaultBranch,
			youtrackBaseURL: settings.youtrackBaseURL
		)
	}
	guard let header = allRows.first(where: { !$0.isWorktree }) else {
		return nil
	}

	let worktrees = sortRepositories(allRows.filter(\.isWorktree), sortMode: sortMode)
	return RepoGroupReducer.State(
		id: rootPath,
		isCollapsed: isCollapsed,
		header: header,
		worktrees: IdentifiedArrayOf(uniqueElements: worktrees),
		settings: settings
	)
}

private func mergeGroupRows(
	into state: inout RepositoryListReducer.State,
	rootPath: String,
	scanned: [ScannedRepository]
) {
	guard let group = state.repositoryGroups[id: rootPath] else {
		return
	}

	var currentByPath: [String: RepositoryRowReducer.State] = [group.header.path: group.header]
	for row in group.worktrees {
		currentByPath[row.path] = row
	}

	let rowSettings = state.groupSettings[rootPath] ?? RepoGroupSettings()
	let effectiveMobileSubfolder = (rowSettings.supportsIOS && rowSettings.supportsAndroid)
		? rowSettings.mobileSubfolderPath
		: ""

	var updated: [RepositoryRowReducer.State] = []
	for repo in scanned {
		if var existing = currentByPath[repo.path] {
			// Preserve cached data; update only git-derived fields
			existing.name = repo.name
			existing.isWorktree = repo.isWorktree
			existing.branchName = repo.branchName
			updated.append(existing)
		}
		else {
			updated.append(RepositoryRowReducer.State(
				path: repo.path,
				name: repo.name,
				branchName: repo.branchName,
				isWorktree: repo.isWorktree,
				supportsIOS: rowSettings.supportsIOS,
				supportsAndroid: rowSettings.supportsAndroid,
				mobileSubfolderPath: effectiveMobileSubfolder,
				iosSubfolderPath: rowSettings.iosSubfolderPath,
				supportsTuist: rowSettings.supportsTuist,
				ticketIdRegex: rowSettings.ticketIdRegex,
				xcodeFilePreference: rowSettings.xcodeFilePreference,
				supportsWeb: rowSettings.supportsWeb,
				webIndexPath: rowSettings.webIndexPath,
				defaultBranch: rowSettings.defaultBranch,
				youtrackBaseURL: rowSettings.youtrackBaseURL
			))
		}
	}

	guard let newHeader = updated.first(where: { !$0.isWorktree }) else {
		return
	}

	let worktrees = sortRepositories(updated.filter(\.isWorktree), sortMode: state.sortMode)
	state.repositoryGroups[id: rootPath]?.header = newHeader
	state.repositoryGroups[id: rootPath]?.worktrees = IdentifiedArrayOf(uniqueElements: worktrees)
}

// MARK: - Sorting

private func sortRepositories(
	_ repositories: [RepositoryRowReducer.State],
	sortMode: SortMode
) -> [RepositoryRowReducer.State] {
	repositories.sorted { r1, r2 in
		switch sortMode {
		case .state: sortByState(r1, r2)

		case .ticket:
			(r1.ticketId ?? "")
				.localizedCaseInsensitiveCompare(r2.ticketId ?? "") == .orderedDescending

		case .branch:
			(r1.branchName ?? "")
				.localizedCaseInsensitiveCompare(r2.branchName ?? "") == .orderedAscending
		}
	}
}

/// Orders rows by ``TicketStateSection`` — the same buckets the list draws headers for — then by
/// ticket id within a bucket.
private func sortByState(
	_ r1: RepositoryRowReducer.State,
	_ r2: RepositoryRowReducer.State
) -> Bool {
	let s1 = TicketStateSection(row: r1)
	let s2 = TicketStateSection(row: r2)
	if s1 != s2 {
		return s1 < s2
	}
	return (r1.ticketId ?? "").localizedCaseInsensitiveCompare(r2.ticketId ?? "") == .orderedDescending
}

private func applySettings(
	_ settings: RepoGroupSettings,
	to row: inout RepositoryRowReducer.State
) {
	let effectiveMobileSubfolder = (settings.supportsIOS && settings.supportsAndroid)
		? settings.mobileSubfolderPath
		: ""
	row.supportsIOS = settings.supportsIOS
	row.supportsAndroid = settings.supportsAndroid
	row.mobileSubfolderPath = effectiveMobileSubfolder
	row.iosSubfolderPath = settings.iosSubfolderPath
	row.supportsTuist = settings.supportsTuist
	row.ticketIdRegex = settings.ticketIdRegex
	row.youtrackBaseURL = settings.youtrackBaseURL
	let newTicketId = settings.ticketIdRegex.isEmpty
		? nil
		: GitBranchDetector.extractTicketId(from: row.branchName ?? row.name, pattern: settings.ticketIdRegex)
	row.ticketId = newTicketId
	row.ticketButton = newTicketId.flatMap { id in
		YouTrackURLBuilder.issueURL(baseURL: settings.youtrackBaseURL, ticketId: id)
			.map { TicketButtonReducer.State(ticketId: id, ticketURL: $0) }
	}
	row.shareButton.updateTicketURL(row.ticketButton?.ticketURL ?? "")
	row.tuistButton.iosSubfolderPath = settings.iosSubfolderPath
	row.xcodeButton.iosSubfolderPath = settings.iosSubfolderPath
	row.xcodeButton.xcodeFilePreference = settings.xcodeFilePreference
	row.androidStudioButton.mobileSubfolderPath = effectiveMobileSubfolder
	row.terminalButton.mobileSubfolderPath = effectiveMobileSubfolder
	row.claudeCodeButton.mobileSubfolderPath = effectiveMobileSubfolder
	if settings.supportsWeb, !settings.webIndexPath.isEmpty {
		row.webButton = .init(
			repositoryPath: row.path,
			webIndexPath: settings.webIndexPath
		)
	}
	else {
		row.webButton = nil
	}
	row.defaultBranch = settings.defaultBranch
	row.gitActionsMenu.setDefaultBranch(settings.defaultBranch)
}

private func findRowState(
	for path: String,
	in state: RepositoryListReducer.State
) -> RepositoryRowReducer.State? {
	for group in state.repositoryGroups {
		if group.header.path == path { return group.header }
		if let wt = group.worktrees[id: path] { return wt }
	}
	return nil
}

private func refreshRow(
	for path: String,
	in state: RepositoryListReducer.State
) -> EffectOf<RepositoryListReducer> {
	sendToRow(.refresh, for: path, in: state)
}

private func sendToRow(
	_ action: RepositoryRowReducer.Action,
	for path: String,
	in state: RepositoryListReducer.State
) -> EffectOf<RepositoryListReducer> {
	for group in state.repositoryGroups {
		if group.header.path == path {
			return .send(.repositoryGroups(.element(id: group.id, action: .header(action))))
		}
		if group.worktrees[id: path] != nil {
			return .send(.repositoryGroups(.element(
				id: group.id,
				action: .worktrees(.element(id: path, action: action))
			)))
		}
	}
	return .none
}

private func groupId(
	containing path: String,
	in state: RepositoryListReducer.State
) -> String? {
	state.repositoryGroups.first { group in
		group.header.path == path || group.worktrees[id: path] != nil
	}?.id
}

private func groupSettings(
	for repositoryPath: String,
	in state: RepositoryListReducer.State
) -> RepoGroupSettings {
	for group in state.repositoryGroups {
		if group.header.path == repositoryPath || group.worktrees[id: repositoryPath] != nil {
			return state.groupSettings[group.id] ?? RepoGroupSettings()
		}
	}
	return RepoGroupSettings()
}

/// The group's own command when it has one, otherwise the global one — unless the group opted
/// out of the global command, in which case its tabs start idle.
private func startupCommand(
	for repoSettings: RepoGroupSettings,
	in state: RepositoryListReducer.State
) -> String {
	let own = repoSettings.terminalStartupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
	if !own.isEmpty { return own }
	return repoSettings.skipGlobalTerminalStartupCommand ? "" : state.terminalStartupCommand
}

#if DEBUG
extension RepositoryListReducer.State {
	/// Write access for `TestStore` assertions, which describe an expected change by mutating
	/// state — a row's, here, reached through the list. Debug builds only, and in this file
	/// because nothing else can use `repositoryGroups`' setter.
	var repositoryGroupsForTesting: IdentifiedArrayOf<RepoGroupReducer.State> {
		get { repositoryGroups }
		set { repositoryGroups = newValue }
	}
}
#endif
