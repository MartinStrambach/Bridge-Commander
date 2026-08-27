import ComposableArchitecture
import Foundation
import GitCore
internal import OrderedCollections
import Settings
import SwiftUI
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

		var terminalSessions: IdentifiedArrayOf<TerminalSession> = []
		var terminalLayout: TerminalLayoutReducer.State?

		@Shared(.trackedRepoPaths)
		fileprivate(set) var trackedRepoPaths: [String] = []

		@Shared(.collapsedRepoPaths)
		fileprivate(set) var collapsedRepoPaths: [String] = []

		@Shared(.periodicRefreshInterval)
		fileprivate(set) var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Shared(.groupSettings)
		fileprivate(set) var groupSettings: [String: RepoGroupSettings] = [:]

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

	enum Action: ViewAction {
		case view(ViewAction)
		case addRepository(String)
		case addRepositoryFailed(String)
		case addRepositorySucceeded(rootPath: String, scanned: [ScannedRepository])
		case alert(PresentationAction<Alert>)
		case checkAccessibilityPermission
		case checkPermissions
		case checkSystemEventsPermission
		case didReceiveSystemEventsPermission(Bool)
		case didScanGroup(rootPath: String, rows: [ScannedRepository])
		case refreshRepositories
		case repositoryGroups(IdentifiedActionOf<RepoGroupReducer>)
		case scanCompleted
		case scanFailed
		case performDebouncedSort
		case startPeriodicRefresh
		case startScan
		case stopPeriodicRefresh
		case terminalLayout(TerminalLayoutReducer.Action)

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
			case searchTextChanged(String)
			case showTerminalsRequested
			case sortModeButtonTapped
		}

		enum Alert: Equatable {
			case dismiss
		}
	}

	private nonisolated enum CancellableId: Hashable {
		case periodicRefresh
		case scan
		case sortAfterFetch
	}

	@Dependency(LastOpenedDirectoryClient.self)
	private var lastOpenedDirectoryClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			// MARK: - View Actions

			case .view(.onAppear):
				return .merge(.send(.startScan), .send(.startPeriodicRefresh), .send(.checkPermissions))

			case .view(.didBecomeActive):
				return .send(.checkPermissions)

			case .stopPeriodicRefresh,
			     .view(.onDisappear):
				return .cancel(id: CancellableId.periodicRefresh)

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
				withAnimation {
					switch state.sortMode {
					case .state: state.sortMode = .ticket
					case .ticket: state.sortMode = .branch
					case .branch: state.sortMode = .state
					}
					sortGroupsInState(in: &state)
				}
				return .none

			case let .view(.activeTerminalFilterChanged(isOn)):
				withAnimation {
					state.showsActiveTerminalsOnly = isOn
				}
				return .none

			case let .view(.searchTextChanged(text)):
				state.searchText = text
				return .none

			case .view(.clearButtonTapped):
				state.repositoryGroups.removeAll()
				state.$trackedRepoPaths.withLock { $0.removeAll() }
				state.$collapsedRepoPaths.withLock { $0.removeAll() }
				state.isScanning = false
				return .cancel(id: CancellableId.periodicRefresh)

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
				return .send(.refreshRepositories)

			case .view(.openHomeTerminalButtonTapped):
				return openTerminal(for: NSHomeDirectory(), in: &state)

			case .view(.showTerminalsRequested):
				guard state.terminalLayout == nil else {
					return .none
				}
				// Prefer a live session so the panel opens on a working terminal
				// rather than a lingering failed tab.
				guard
					let session = state.terminalSessions.first(where: \.status.isLive)
						?? state.terminalSessions.first
				else {
					return .none
				}
				return openTerminal(for: session.repositoryPath, in: &state)

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
					sortGroupsByName(in: &state)
				}
				return .none

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

			case let .repositoryGroups(.element(id: groupId, action: .header(.worktreeCreated))),
			     let .repositoryGroups(.element(id: groupId, action: .worktrees(.element(_, .worktreeCreated)))):
				state.isScanning = true
				return .run { [groupId] send in
					let rows = await GitWorktreeScanner.listWorktrees(forRepo: groupId)
					await send(.didScanGroup(rootPath: groupId, rows: rows))
					await send(.scanCompleted)
				}
				.cancellable(id: CancellableId.scan)

			case let .repositoryGroups(.element(id: groupId, action: .worktrees(.element(id: worktreePath, .worktreeDeleted)))):
				let toRemove = state.terminalSessions
					.filter { $0.repositoryPath == worktreePath }
					.map(\.id)
				for sessionId in toRemove {
					state.terminalSessions.remove(id: sessionId)
				}
				if state.terminalLayout?.activeRepositoryPath == worktreePath {
					if let next = state.terminalSessions.first {
						state.terminalLayout?.activeRepositoryPath = next.repositoryPath
						state.terminalLayout?.activeSessionId = next.id
					}
					else {
						state.terminalLayout = nil
					}
				}
				state.isScanning = true
				return .run { [groupId] send in
					let rows = await GitWorktreeScanner.listWorktrees(forRepo: groupId)
					await send(.didScanGroup(rootPath: groupId, rows: rows))
					await send(.scanCompleted)
				}
				.cancellable(id: CancellableId.scan)

			// MARK: - Scan Results

			case let .didScanGroup(rootPath, scanned):
				if state.repositoryGroups[id: rootPath] != nil {
					// Existing group: merge rows, preserving cached PR/ticket data
					mergeGroupRows(into: &state, rootPath: rootPath, scanned: scanned)
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
						sortGroupsByName(in: &state)
					}
				}
				return .none

			case .scanCompleted,
			     .scanFailed:
				state.isScanning = false
				return .none

			// MARK: - Refresh

			case .refreshRepositories:
				guard !state.repositoryGroups.isEmpty else {
					return .none
				}

				// Capture only the ids (Sendable) and rebuild the actions inside the effect.
				let refreshTargets = state.repositoryGroups.map { group in
					(groupId: group.id, worktreeIds: group.worktrees.map(\.id))
				}
				// Send the refreshes sequentially instead of merging to stagger row refreshes.
				// Merging all effects at once spawns 7×N git processes simultaneously (thundering herd).
				// Sequencing them means git load ramps up gradually.
				return .run { send in
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
				let interval = state.periodicRefreshInterval.timeInterval
				return .run { send in
					while true {
						try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
						await send(.refreshRepositories)
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
				return .none

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

			// MARK: - Terminal git menu sync

			// Fired once per row status fetch (see RepositoryRowReducer.didFetchStatus), by which
			// point the row's own menu state is already updated — copy it into the terminal header's
			// menu when that row is the one opened in the terminal.
			case let .repositoryGroups(.element(id: groupId, action: .header(.gitActionsMenu(.didCheckGitStatus)))):
				guard let path = state.repositoryGroups[id: groupId]?.header.path else {
					return .none
				}
				return syncTerminalGitMenu(for: path, in: &state)

			case let .repositoryGroups(.element(_, .worktrees(.element(id: path, .gitActionsMenu(.didCheckGitStatus))))):
				return syncTerminalGitMenu(for: path, in: &state)

			// MARK: - Terminal Layout

			case let .terminalLayout(.selectRepo(repositoryPath)):
				if
					let existing = state.terminalSessions.first(where: {
						$0.repositoryPath == repositoryPath
					})
				{
					state.terminalLayout?.activeSessionId = existing.id
				}
				else {
					let repoSettings = groupSettings(for: repositoryPath, in: state)
					let subfolder: String =
						if repoSettings.supportsIOS, repoSettings.supportsAndroid {
							repoSettings.mobileSubfolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
						}
						else {
							""
						}
					let startingDirectory = (repositoryPath as NSString).appendingPathComponent(subfolder)
					let session = TerminalSession(
						repositoryPath: repositoryPath,
						startingDirectory: startingDirectory
					)
					state.terminalSessions.append(session)
					state.terminalLayout?.activeSessionId = session.id
				}
				syncTerminalButtons(for: repositoryPath, in: &state)
				return .none

			case .terminalLayout(.hideTerminalMode):
				state.terminalLayout = nil
				return .none

			case .terminalLayout(.newTabRequested):
				guard let path = state.terminalLayout?.activeRepositoryPath else {
					return .none
				}

				let maxIndex = state.terminalSessions
					.filter { $0.repositoryPath == path }
					.map(\.tabIndex)
					.max() ?? 0
				let session = TerminalSession(repositoryPath: path, tabIndex: maxIndex + 1)
				state.terminalSessions.append(session)
				state.terminalLayout?.activeSessionId = session.id
				return .none

			case let .terminalLayout(.selectTab(sessionId)):
				if let session = state.terminalSessions[id: sessionId] {
					state.terminalLayout?.activeRepositoryPath = session.repositoryPath
					state.terminalLayout?.activeSessionId = sessionId
				}
				return .none

			case let .terminalLayout(.killTab(sessionId)):
				guard let session = state.terminalSessions[id: sessionId] else {
					return .none
				}

				let repoPath = session.repositoryPath
				state.terminalSessions.remove(id: sessionId)
				if state.terminalLayout?.activeSessionId == sessionId {
					if let next = state.terminalSessions.first(where: { $0.repositoryPath == repoPath }) {
						state.terminalLayout?.activeSessionId = next.id
					}
					else if let next = state.terminalSessions.first {
						state.terminalLayout?.activeRepositoryPath = next.repositoryPath
						state.terminalLayout?.activeSessionId = next.id
					}
					else {
						state.terminalLayout = nil
					}
				}
				return .none

			case let .terminalLayout(.killRepo(repositoryPath)):
				let toRemove = state.terminalSessions
					.filter { $0.repositoryPath == repositoryPath }
					.map(\.id)
				for id in toRemove {
					state.terminalSessions.remove(id: id)
				}
				if state.terminalLayout?.activeRepositoryPath == repositoryPath {
					if let next = state.terminalSessions.first {
						state.terminalLayout?.activeRepositoryPath = next.repositoryPath
						state.terminalLayout?.activeSessionId = next.id
					}
					else {
						state.terminalLayout = nil
					}
				}
				return .none

			case let .terminalLayout(.retryTab(sessionId)):
				guard let old = state.terminalSessions[id: sessionId] else {
					return .none
				}

				let repoPath = old.repositoryPath
				let tabIndex = old.tabIndex
				state.terminalSessions.remove(id: sessionId)
				let newSession = TerminalSession(repositoryPath: repoPath, tabIndex: tabIndex)
				state.terminalSessions.append(newSession)
				state.terminalLayout?.activeSessionId = newSession.id
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
				guard let path = state.terminalLayout?.activeRepositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case .terminalLayout(.stagingDetail(.dismiss)):
				// Parity with RepositoryRowReducer.repositoryDetail(.dismiss), which covers the
				// same sheet opened from a row: a commit or push made inside it changes the row's
				// counts, so re-run its status fetch once the sheet closes.
				guard let path = state.terminalLayout?.activeRepositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case let .terminalLayout(.sessionStatusChanged(sessionId, status)):
				state.terminalSessions[id: sessionId]?.status = status
				return .none

			case .terminalLayout(.refreshActiveRepoRequested):
				// ⌘R in terminal mode refreshes just the opened repo. The home-directory
				// session has no repo row, so refreshRow falls through to .none there.
				guard let path = state.terminalLayout?.activeRepositoryPath else {
					return .none
				}
				return refreshRow(for: path, in: state)

			case let .terminalLayout(.gitActionsMenu(menuAction)):
				// Same completion routing as RepositoryRowReducer.gitActionsMenu: a finished
				// operation re-runs the row's status fetch, which then syncs back into this copy.
				switch menuAction {
				case .abortMergeButton(.abortMergeCompleted),
				     .discardButton(.discardCompleted),
				     .fetchButton(.fetchCompleted),
				     .mergeMasterButton(.mergeMasterCompleted),
				     .pullButton(.pullCompleted),
				     .pushButton(.pushCompleted),
				     .stashButton(.stashCompleted),
				     .stashButton(.stashPopCompleted):
					guard let path = state.terminalLayout?.activeRepositoryPath else {
						return .none
					}
					return refreshRow(for: path, in: state)

				default:
					return .none
				}

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
		.ifLet(\.terminalLayout, action: \.terminalLayout) {
			TerminalLayoutReducer()
		}
	}
}

// MARK: - Private Free Functions

/// Sorts the top-level repository groups alphabetically by header name.
/// Called once whenever a group is added so the list never re-sorts while rendering.
private func sortGroupsByName(in state: inout RepositoryListReducer.State) {
	state.repositoryGroups.sort {
		$0.header.name.localizedCaseInsensitiveCompare($1.header.name) == .orderedAscending
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

@discardableResult
private func openTerminal(
	for repositoryPath: String,
	in state: inout RepositoryListReducer.State
) -> EffectOf<RepositoryListReducer> {
	let existingSession = state.terminalSessions.first(where: { $0.repositoryPath == repositoryPath })
	let session: TerminalSession
	if let existing = existingSession {
		session = existing
	}
	else {
		let repoSettings = groupSettings(for: repositoryPath, in: state)
		let subfolder: String =
			if repoSettings.supportsIOS, repoSettings.supportsAndroid {
				repoSettings.mobileSubfolderPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			}
			else {
				""
			}
		let startingDirectory = (repositoryPath as NSString).appendingPathComponent(subfolder)
		session = TerminalSession(repositoryPath: repositoryPath, startingDirectory: startingDirectory)
		state.terminalSessions.append(session)
	}
	if state.terminalLayout == nil {
		state.terminalLayout = TerminalLayoutReducer.State(
			activeRepositoryPath: repositoryPath,
			activeSessionId: session.id
		)
	}
	else {
		state.terminalLayout?.activeRepositoryPath = repositoryPath
		state.terminalLayout?.activeSessionId = session.id
	}
	syncTerminalButtons(for: repositoryPath, in: &state)
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
			defaultBranch: settings.defaultBranch
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
				defaultBranch: rowSettings.defaultBranch
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
	let newTicketId = settings.ticketIdRegex.isEmpty
		? nil
		: GitBranchDetector.extractTicketId(from: row.branchName ?? row.name, pattern: settings.ticketIdRegex)
	row.ticketId = newTicketId
	row.ticketButton = newTicketId.map { TicketButtonReducer.State(ticketId: $0) }
	let newTicketURL = newTicketId.map { "https://youtrack.livesport.eu/issue/\($0)" } ?? ""
	row.shareButton.updateTicketURL(newTicketURL)
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

private func syncTerminalButtons(for path: String, in state: inout RepositoryListReducer.State) {
	guard let rowState = findRowState(for: path, in: state) else {
		state.terminalLayout?.xcodeButton = nil
		state.terminalLayout?.androidStudioButton = nil
		state.terminalLayout?.webButton = nil
		state.terminalLayout?.tuistButton = nil
		state.terminalLayout?.ticketButton = nil
		state.terminalLayout?.gitActionsMenu = nil
		return
	}
	state.terminalLayout?.xcodeButton = rowState.supportsIOS ? rowState.xcodeButton : nil
	state.terminalLayout?.androidStudioButton = rowState.supportsAndroid ? rowState.androidStudioButton : nil
	state.terminalLayout?.webButton = rowState.webButton
	state.terminalLayout?.tuistButton = terminalTuistButton(for: rowState)
	state.terminalLayout?.ticketButton = rowState.ticketButton
	state.terminalLayout?.gitActionsMenu = rowState.gitActionsMenu
}

/// The terminal header's git menu is a copy of the row's state (see `syncTerminalButtons`),
/// synced only when a repo is opened or selected. The fields gating which menu items show
/// (remote branch, unpushed count, stash/discard flags, merge status) must be re-copied
/// whenever the row's status fetch lands, or the copy drifts from reality.
private func syncTerminalGitMenu(
	for path: String,
	in state: inout RepositoryListReducer.State
) -> EffectOf<RepositoryListReducer> {
	guard
		state.terminalLayout?.activeRepositoryPath == path,
		state.terminalLayout?.gitActionsMenu != nil,
		let rowState = findRowState(for: path, in: state)
	else {
		return .none
	}

	let rowMenu = rowState.gitActionsMenu
	state.terminalLayout?.gitActionsMenu?.currentBranch = rowMenu.currentBranch
	state.terminalLayout?.gitActionsMenu?.isMergeInProgress = rowMenu.isMergeInProgress
	state.terminalLayout?.gitActionsMenu?.hasRemoteBranch = rowMenu.hasRemoteBranch
	state.terminalLayout?.gitActionsMenu?.unpushedCommitsCount = rowMenu.unpushedCommitsCount
	state.terminalLayout?.gitActionsMenu?.stashButton.hasChanges = rowMenu.stashButton.hasChanges
	state.terminalLayout?.gitActionsMenu?.discardButton.hasTrackedChanges = rowMenu.discardButton.hasTrackedChanges
	state.terminalLayout?.gitActionsMenu?.discardButton.hasUntrackedFiles = rowMenu.discardButton.hasUntrackedFiles
	state.terminalLayout?.gitActionsMenu?.setDefaultBranch(rowMenu.defaultBranch)
	// The stash-list state is internal to the menu, so the copy re-checks it itself.
	return .send(.terminalLayout(.gitActionsMenu(.refresh)))
}

/// The terminal header shows the Tuist menu under the same gate as the repository row:
/// the group must support both iOS and Tuist.
func terminalTuistButton(for rowState: RepositoryRowReducer.State?) -> TuistButtonReducer.State? {
	guard let rowState, rowState.supportsIOS, rowState.supportsTuist else {
		return nil
	}
	return rowState.tuistButton
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
	for group in state.repositoryGroups {
		if group.header.path == path {
			return .send(.repositoryGroups(.element(id: group.id, action: .header(.refresh))))
		}
		if group.worktrees[id: path] != nil {
			return .send(.repositoryGroups(.element(
				id: group.id,
				action: .worktrees(.element(id: path, action: .refresh))
			)))
		}
	}
	return .none
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
