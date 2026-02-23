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
		fileprivate(set) var selectedDirectory: String?

		fileprivate(set) var sortMode: SortMode = .state

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

		enum ViewAction: Sendable {
			case clearButtonTapped
			case directorySelected(String)
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
				state.selectedDirectory = nil
				state.isScanning = false
				lastOpenedDirectoryClient.clear()
				return .cancel(id: CancellableId.periodicRefresh)

			case let .view(.directorySelected(directory)):
				lastOpenedDirectoryClient.save(directory)
				state.selectedDirectory = directory
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

			case .repositories(.element(_, .worktreeCreated)),
			     .repositories(.element(_, .worktreeDeleted)),
			     .startScan:
				// Only load from service if no directory is set
				if state.selectedDirectory == nil {
					state.selectedDirectory = lastOpenedDirectoryClient.load()
				}

				guard let directory = state.selectedDirectory else {
					return .none
				}

				state.isScanning = true

				return .merge(
					.send(.checkSystemEventsPermission),
					.run { send in
						do {
							let scanned = try await scanRepositories(in: directory)
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

			case .repositories:
				return .none
			}
		}
		.forEach(\.repositories, action: \.repositories) {
			RepositoryRowReducer()
		}
	}

	// MARK: - Private Helpers

	private func sortRepositoriesInState(in state: inout State) {
		let sorted = sortRepositories(Array(state.repositories), sortMode: state.sortMode)
		state.repositories = IdentifiedArrayOf(uniqueElements: sorted)
	}
}

// MARK: - Private Helpers

private func scanRepositories(in directory: String) async throws -> [ScannedRepository] {
	let url = URL(fileURLWithPath: directory)
	let repositories = await GitDetector.scanForRepositories(at: url)

	return repositories.map { repo in
		let repoURL = URL(fileURLWithPath: repo.path)
		let parentDirectory = repoURL.deletingLastPathComponent().path

		return ScannedRepository(
			path: repo.path,
			name: repo.name,
			directory: parentDirectory,
			isWorktree: repo.isWorktree,
			branchName: repo.branchName,
			isMergeInProgress: repo.isMergeInProgress
		)
	}
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
