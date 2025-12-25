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
		var repositories: IdentifiedArrayOf<RepositoryRowReducer.State> = []
		var isScanning = false
		var selectedDirectory: String?

		var sortMode: SortMode = .state

		@Shared(.appStorage("periodicRefreshInterval"))
		var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes
	}

	enum Action: Sendable {
		case clearResults
		case didScanRepositories([ScannedRepository])
		case scanFailed(String)
		case setDirectory(String)
		case startScan
		case refreshRepositories
		case repositories(IdentifiedActionOf<RepositoryRowReducer>)
		case startPeriodicRefresh
		case stopPeriodicRefresh
		case toggleSortMode
	}

	private nonisolated enum CancellableId: Hashable, Sendable {
		case periodicRefresh
	}

	@Dependency(\.lastOpenedDirectoryService)
	private var lastOpenedDirectoryService

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .setDirectory(directory):
				lastOpenedDirectoryService.save(directory)
				state.selectedDirectory = directory
				return .none

			case .startScan:
				state.selectedDirectory = lastOpenedDirectoryService.load()
				guard let directory = state.selectedDirectory else {
					return .none
				}

				state.isScanning = true

				return .run { send in
					do {
						let scanned = try await scanRepositories(in: directory)
						await send(.didScanRepositories(scanned))
					}
					catch {
						await send(.scanFailed(error.localizedDescription))
					}
				}

			case let .didScanRepositories(scannedRepos):
				state.isScanning = false
				mergeRepositories(into: &state, scanned: scannedRepos)
				return .none

			case .scanFailed:
				state.isScanning = false
				return .none

			case .refreshRepositories:
				guard !state.repositories.isEmpty else {
					return .none
				}

				var effects: [Effect<Action>] = []
				for repository in state.repositories {
					effects.append(
						.send(.repositories(.element(id: repository.id, action: .requestRefresh)))
					)
				}
				return .concatenate(.send(.startScan), .merge(effects))

			case .startPeriodicRefresh:
				let interval = state.periodicRefreshInterval.timeInterval
				return .run { send in
					while true {
						try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
						await send(.refreshRepositories)
					}
				}
				.cancellable(id: CancellableId.periodicRefresh, cancelInFlight: true)

			case .stopPeriodicRefresh:
				return .cancel(id: CancellableId.periodicRefresh)

			case .clearResults:
				state.repositories.removeAll()
				state.selectedDirectory = nil
				state.isScanning = false
				lastOpenedDirectoryService.clear()
				return .cancel(id: CancellableId.periodicRefresh)

			case .toggleSortMode:
				withAnimation {
					// Cycle through sort modes: state -> ticket -> branch -> state
					switch state.sortMode {
					case .state:
						state.sortMode = .ticket
					case .ticket:
						state.sortMode = .branch
					case .branch:
						state.sortMode = .state
					}
					state.repositories = .init(
						uniqueElements: sortRepositories(Array(state.repositories), sortMode: state.sortMode)
					)
				}
				return .none

			case .repositories(.element(_, .worktreeCreated)),
			     .repositories(.element(_, .worktreeDeleted)):
				return .send(.startScan)

			case .repositories(.element(_, .didFetchYouTrack)):
				// Re-sort when ticket state is fetched (if sorting by state)
				if state.sortMode == .state {
					withAnimation {
						state.repositories = .init(
							uniqueElements: sortRepositories(Array(state.repositories), sortMode: state.sortMode)
						)
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
}

// MARK: - Private Helpers

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
	// Define priority order: inProgress (highest) -> others -> done (lowest)
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
		return 5
	}

	// nil states go near the end

	switch state {
	case .inProgress:
		return 0 // Highest priority - at the top
	case .waitingToCodeReview:
		return 1
	case .waitingForTesting:
		return 2
	case .waitingToAcceptation:
		return 3
	case .accepted:
		return 4
	case .open:
		return 5
	case .done:
		return 6 // Lowest priority - at the bottom
	}
}

private func scanRepositories(in directory: String) async throws -> [ScannedRepository] {
	let url = URL(fileURLWithPath: directory)
	let repositories = await GitDetector.scanForRepositories(at: url)

	return repositories.map { repo in
		ScannedRepository(
			path: repo.path,
			name: repo.name,
			directory: repo.path.split(separator: "/").dropLast().joined(separator: "/"),
			isWorktree: repo.isWorktree,
			branchName: repo.branchName,
			isMergeInProgress: repo.isMergeInProgress,
		)
	}
}

private func mergeRepositories(into state: inout RepositoryListReducer.State, scanned: [ScannedRepository]) {
	// Create a mapping of current repositories by path
	var currentReposByPath: [String: RepositoryRowReducer.State] = [:]
	for repo in state.repositories {
		currentReposByPath[repo.path] = repo
	}

	// Start with updated repos
	var updatedRepos: [RepositoryRowReducer.State] = []

	for scannedRepo in scanned {
		if let existing = currentReposByPath[scannedRepo.path] {
			// Update existing repo with new scan data, preserve cached info
			var updated = existing
			updated.name = scannedRepo.name
			updated.isWorktree = scannedRepo.isWorktree
			updated.branchName = scannedRepo.branchName
			// Keep: prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName, unpushedCommitCount
			updatedRepos.append(updated)
		}
		else {
			// New repo
			var newRepo = RepositoryRowReducer.State(
				path: scannedRepo.path,
				name: scannedRepo.name,
				isWorktree: scannedRepo.isWorktree
			)
			newRepo.branchName = scannedRepo.branchName
			updatedRepos.append(newRepo)
		}
	}

	// Sort based on current sort mode
	let sortedRepos = sortRepositories(updatedRepos, sortMode: state.sortMode)
	state.repositories = IdentifiedArrayOf(uniqueElements: sortedRepos)
}
