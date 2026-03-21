import ComposableArchitecture
import Foundation
import SwiftUI

enum SortMode: String, Equatable, Sendable {
	case state = "State"
	case ticket = "Ticket"
	case branch = "Branch"
}

@Reducer
struct RepositoryListReducer {
	@ObservableState
	struct State: Equatable {
		fileprivate(set) var repositories: IdentifiedArrayOf<RepositoryRowReducer.State> = []
		fileprivate(set) var isScanning = false
		fileprivate(set) var selectedRepository: String?

		fileprivate(set) var sortMode: SortMode = .state

		var terminalSessions: IdentifiedArrayOf<TerminalSession> = []
		var terminalLayout: TerminalLayoutReducer.State?

		@Shared(.periodicRefreshInterval)
		fileprivate(set) var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		fileprivate var isSystemEventsPermissionGranted: Bool?
		fileprivate var isPermissionWarningDismissed = false

		var showPermissionDialog: Bool {
			isSystemEventsPermissionGranted == false && !isPermissionWarningDismissed
		}
	}

	enum Action: ViewAction, Sendable {
		case view(ViewAction)
		case checkSystemEventsPermission
		case didReceiveSystemEventsPermission(Bool)
		case didScanRepositories([ScannedRepository])
		case refreshRepositories
		case repositories(IdentifiedActionOf<RepositoryRowReducer>)
		case scanFailed
		case startPeriodicRefresh
		case startScan
		case stopPeriodicRefresh
		case terminalLayout(TerminalLayoutReducer.Action)

		enum ViewAction: Sendable {
			case clearButtonTapped
			case repositorySelected(String)
			case dismissPermissionWarningButtonTapped
			case onAppear
			case onDisappear
			case openAutomationSettingsButtonTapped
			case periodicRefreshIntervalChanged
			case refreshButtonTapped
			case sortModeButtonTapped
		}
	}

	private nonisolated enum CancellableId: Hashable, Sendable {
		case periodicRefresh
	}

	@Dependency(LastOpenedDirectoryClient.self)
	private var lastOpenedDirectoryClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .view(.onAppear):
				return .merge(.send(.startScan), .send(.startPeriodicRefresh))

			case .view(.periodicRefreshIntervalChanged):
				return .concatenate(.send(.stopPeriodicRefresh), .send(.startPeriodicRefresh))

			case .view(.sortModeButtonTapped):
				withAnimation {
					switch state.sortMode {
					case .state:
						state.sortMode = .ticket
					case .ticket:
						state.sortMode = .branch
					case .branch:
						state.sortMode = .state
					}
					sortRepositoriesInState(in: &state)
				}
				return .none

			case .view(.clearButtonTapped):
				state.repositories.removeAll()
				state.selectedRepository = nil
				state.isScanning = false
				lastOpenedDirectoryClient.clear()
				return .cancel(id: CancellableId.periodicRefresh)

			case let .view(.repositorySelected(directory)):
				lastOpenedDirectoryClient.save(directory)
				state.selectedRepository = directory
				return .send(.startScan)

			case .view(.openAutomationSettingsButtonTapped):
				return .run { _ in
					if
						let url =
						URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
					{
						NSWorkspace.shared.open(url)
					}
				}

			case .view(.dismissPermissionWarningButtonTapped):
				state.isPermissionWarningDismissed = true
				return .none

			case let .repositories(.element(id: repositoryPath, action: .openTerminalForRepo)):
				let existingSession = state.terminalSessions.first(where: { $0.repositoryPath == repositoryPath })
				let session: TerminalSession
				if let existing = existingSession {
					session = existing
				} else {
					session = TerminalSession(repositoryPath: repositoryPath)
					state.terminalSessions.append(session)
				}
				if state.terminalLayout == nil {
					state.terminalLayout = TerminalLayoutReducer.State(
						activeRepositoryPath: repositoryPath,
						activeSessionId: session.id
					)
				} else {
					state.terminalLayout?.activeRepositoryPath = repositoryPath
					state.terminalLayout?.activeSessionId = session.id
				}
				return .none

			case .repositories(.element(_, .worktreeCreated)),
			     .repositories(.element(_, .worktreeDeleted)),
			     .startScan:
				// Only load from service if no repository is set
				if state.selectedRepository == nil {
					state.selectedRepository = lastOpenedDirectoryClient.load()
				}

				guard let directory = state.selectedRepository else {
					return .none
				}

				state.isScanning = true

				return .merge(
					.send(.checkSystemEventsPermission),
					.run { send in
						do {
							let scanned = try await scanRepository(directory)
							await send(.didScanRepositories(scanned))
						}
						catch {
							print("Scan failed: \(error.localizedDescription)")
							await send(.scanFailed)
						}
					}
				)

			case let .didScanRepositories(scannedRepos):
				state.isScanning = false
				mergeRepositories(into: &state, scanned: scannedRepos)
				return .none

			case .scanFailed:
				state.isScanning = false
				return .none

			case .view(.refreshButtonTapped):
				state.isSystemEventsPermissionGranted = nil
				return .send(.refreshRepositories)

			case .refreshRepositories:
				guard !state.repositories.isEmpty else {
					return .none
				}

				let refreshEffects = state.repositories.map { repository in
					Effect<Action>.send(.repositories(.element(id: repository.id, action: .refresh)))
				}

				return .concatenate(.send(.startScan), .merge(refreshEffects))

			case .startPeriodicRefresh:
				let interval = state.periodicRefreshInterval.timeInterval
				return .run { send in
					while true {
						try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
						await send(.refreshRepositories)
					}
				}
				.cancellable(id: CancellableId.periodicRefresh, cancelInFlight: true)

			case .stopPeriodicRefresh,
			     .view(.onDisappear):
				return .cancel(id: CancellableId.periodicRefresh)

			case .checkSystemEventsPermission:
				guard state.isSystemEventsPermissionGranted == nil else {
					return .none
				}

				return .run { send in
					let granted = await PermissionChecker.isSystemEventsAutomationPermitted()
					await send(.didReceiveSystemEventsPermission(granted))
				}

			case let .didReceiveSystemEventsPermission(granted):
				state.isSystemEventsPermissionGranted = granted
				return .none

			case .repositories(.element(_, .didFetchYouTrack)):
				// Re-sort when ticket state is fetched (if sorting by state)
				// Only sort if we're in state mode to avoid unnecessary work
				if state.sortMode == .state {
					withAnimation {
						sortRepositoriesInState(in: &state)
					}
				}
				return .none

			case let .terminalLayout(.selectRepo(repositoryPath)):
				// Create session if not yet open for this repo
				if let existing = state.terminalSessions.first(where: { $0.repositoryPath == repositoryPath }) {
					state.terminalLayout?.activeSessionId = existing.id
				} else {
					let session = TerminalSession(repositoryPath: repositoryPath)
					state.terminalSessions.append(session)
					state.terminalLayout?.activeSessionId = session.id
				}
				return .none

			case .terminalLayout(.hideTerminalMode):
				state.terminalLayout = nil
				return .none

			case let .terminalLayout(.newTabRequested):
				guard let path = state.terminalLayout?.activeRepositoryPath else { return .none }
				let maxIndex = state.terminalSessions.filter { $0.repositoryPath == path }.map(\.tabIndex).max() ?? 0
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
				guard let session = state.terminalSessions[id: sessionId] else { return .none }
				let repoPath = session.repositoryPath
				state.terminalSessions.remove(id: sessionId)
				// If we killed the active tab, switch to another session
				if state.terminalLayout?.activeSessionId == sessionId {
					if let next = state.terminalSessions.first(where: { $0.repositoryPath == repoPath }) {
						state.terminalLayout?.activeSessionId = next.id
					} else if let next = state.terminalSessions.first {
						state.terminalLayout?.activeRepositoryPath = next.repositoryPath
						state.terminalLayout?.activeSessionId = next.id
					} else {
						state.terminalLayout = nil
					}
				}
				return .none

			case let .terminalLayout(.killRepo(repositoryPath)):
				let toRemove = state.terminalSessions.filter { $0.repositoryPath == repositoryPath }.map { $0.id }
				for id in toRemove {
					state.terminalSessions.remove(id: id)
				}
				if state.terminalLayout?.activeRepositoryPath == repositoryPath {
					if let next = state.terminalSessions.first {
						state.terminalLayout?.activeRepositoryPath = next.repositoryPath
						state.terminalLayout?.activeSessionId = next.id
					} else {
						state.terminalLayout = nil
					}
				}
				return .none

			case let .terminalLayout(.retryTab(sessionId)):
				guard let old = state.terminalSessions[id: sessionId] else { return .none }
				let repoPath = old.repositoryPath
				let tabIndex = old.tabIndex
				state.terminalSessions.remove(id: sessionId)
				let newSession = TerminalSession(repositoryPath: repoPath, tabIndex: tabIndex)
				state.terminalSessions.append(newSession)
				state.terminalLayout?.activeSessionId = newSession.id
				return .none

			case let .terminalLayout(.sessionStatusChanged(sessionId, status)):
				state.terminalSessions[id: sessionId]?.status = status
				return .none

			case .terminalLayout:
				return .none

			case .repositories:
				return .none
			}
		}
		.forEach(\.repositories, action: \.repositories) {
			RepositoryRowReducer()
		}
		.ifLet(\.terminalLayout, action: \.terminalLayout) {
			TerminalLayoutReducer()
		}
	}

	// MARK: - Private Helpers

	private func sortRepositoriesInState(in state: inout State) {
		let sorted = sortRepositories(Array(state.repositories), sortMode: state.sortMode)
		state.repositories = IdentifiedArrayOf(uniqueElements: sorted)
	}
}

// MARK: - Private Helpers

private func scanRepository(_ path: String) async throws -> [ScannedRepository] {
	await GitWorktreeScanner.listWorktrees(forRepo: path)
}

private func mergeRepositories(
	into state: inout RepositoryListReducer.State,
	scanned: [ScannedRepository]
) {
	// Create a mapping of current repositories by path
	var currentReposByPath: [String: RepositoryRowReducer.State] = [:]
	for repo in state.repositories {
		currentReposByPath[repo.path] = repo
	}

	// Build updated repository list
	// Only include repositories that were scanned (this automatically removes deleted ones)
	var updatedRepos: [RepositoryRowReducer.State] = []

	for scannedRepo in scanned {
		if let existing = currentReposByPath[scannedRepo.path] {
			// Update existing repo with new scan data, preserve cached info
			var updated = existing
			updated.name = scannedRepo.name
			updated.isWorktree = scannedRepo.isWorktree
			updated.branchName = scannedRepo.branchName
			// Preserved: prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName,
			//            unpushedCommitCount, ticketState, etc.
			updatedRepos.append(updated)
		}
		else {
			// New repo discovered
			var newRepo = RepositoryRowReducer.State(
				path: scannedRepo.path,
				name: scannedRepo.name,
				branchName: scannedRepo.branchName,
				isWorktree: scannedRepo.isWorktree
			)
			newRepo.branchName = scannedRepo.branchName
			updatedRepos.append(newRepo)
		}
	}

	// Sort using the shared sorting function
	let sorted = sortRepositories(updatedRepos, sortMode: state.sortMode)
	state.repositories = IdentifiedArrayOf(uniqueElements: sorted)
}

// MARK: - Sorting Functions

private func sortRepositories(
	_ repositories: [RepositoryRowReducer.State],
	sortMode: SortMode
) -> [RepositoryRowReducer.State] {
	repositories.sorted { repo1, repo2 in
		switch sortMode {
		case .state:
			return sortByState(repo1, repo2)

		case .ticket:
			let ticket1 = repo1.ticketId ?? ""
			let ticket2 = repo2.ticketId ?? ""
			return ticket1.localizedCaseInsensitiveCompare(ticket2) == .orderedDescending

		case .branch:
			let branch1 = repo1.branchName ?? ""
			let branch2 = repo2.branchName ?? ""
			return branch1.localizedCaseInsensitiveCompare(branch2) == .orderedAscending
		}
	}
}

private func sortByState(
	_ repo1: RepositoryRowReducer.State,
	_ repo2: RepositoryRowReducer.State
) -> Bool {
	let priority1 = stateSortPriority(repo1.ticketState)
	let priority2 = stateSortPriority(repo2.ticketState)

	if priority1 != priority2 {
		return priority1 < priority2 // Lower priority number = higher in list
	}

	// If same state, sort by ticket ID as secondary sort
	let ticket1 = repo1.ticketId ?? ""
	let ticket2 = repo2.ticketId ?? ""
	return ticket1.localizedCaseInsensitiveCompare(ticket2) == .orderedDescending
}

private func stateSortPriority(_ state: TicketState?) -> Int {
	guard let state else {
		return 4 // No ticket (e.g., master) - above accepted
	}

	switch state {
	case .inProgress:
		return 0 // Highest priority - at the top
	case .waitingToCodeReview:
		return 1
	case .waitingForTesting:
		return 2
	case .open:
		return 3
	case .accepted,
	     .waitingToAcceptation:
		return 5
	case .done:
		return 6 // Lowest priority - at the bottom
	}
}
