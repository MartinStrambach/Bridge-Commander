import ComposableArchitecture
import Foundation

@Reducer
struct RepositoryListReducer {
	@ObservableState
	struct State: Equatable {
		var repositories: IdentifiedArrayOf<RepositoryRowReducer.State> = []
		var isScanning: Bool = false
		var selectedDirectory: String?
		var errorMessage: String?

		var sortByTicket: Bool = true
	}

	enum Action: Sendable {
		case clearResults
		case didScanRepositories([ScannedRepository])
		case scanFailed(String)
		case setDirectory(String)
		case startScan
		case refreshRepositories
		case repositories(IdentifiedActionOf<RepositoryRowReducer>)
		case startPeriodicRefresh(TimeInterval)
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
				state.errorMessage = nil
				return .none

			case .startScan:
				state.selectedDirectory = lastOpenedDirectoryService.load()
				guard let directory = state.selectedDirectory else {
					state.errorMessage = "No directory selected"
					return .none
				}

				state.isScanning = true
				state.errorMessage = nil

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

			case let .scanFailed(error):
				state.isScanning = false
				state.errorMessage = error
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
				return .merge(effects)

			case let .startPeriodicRefresh(interval):
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
				state.errorMessage = nil
				state.isScanning = false
				lastOpenedDirectoryService.clear()
				return .cancel(id: CancellableId.periodicRefresh)

			case .toggleSortMode:
				state.sortByTicket.toggle()
				state.repositories = .init(
					uniqueElements: sortRepositories(Array(state.repositories), sortByTicket: state.sortByTicket)
				)
				return .none

			case .repositories(.element(_, .worktreeDeleted)):
				return .send(.startScan)

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
	sortByTicket: Bool
) -> [RepositoryRowReducer.State] {
	repositories.sorted { repo1, repo2 in
		if sortByTicket {
			let ticket1 = repo1.ticketId ?? ""
			let ticket2 = repo2.ticketId ?? ""
			return ticket1.localizedCaseInsensitiveCompare(ticket2) == .orderedDescending
		}
		else {
			let branch1 = repo1.branchName ?? ""
			let branch2 = repo2.branchName ?? ""
			return branch1.localizedCaseInsensitiveCompare(branch2) == .orderedAscending
		}
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
			unstagedChangesCount: repo.unstagedChangesCount,
			stagedChangesCount: repo.stagedChangesCount
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
			updated.isMergeInProgress = scannedRepo.isMergeInProgress
			updated.unstagedChangesCount = scannedRepo.unstagedChangesCount
			updated.stagedChangesCount = scannedRepo.stagedChangesCount
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
			newRepo.isMergeInProgress = scannedRepo.isMergeInProgress
			newRepo.unstagedChangesCount = scannedRepo.unstagedChangesCount
			newRepo.stagedChangesCount = scannedRepo.stagedChangesCount
			updatedRepos.append(newRepo)
		}
	}

	// Sort based on current sort mode
	let sortedRepos = sortRepositories(updatedRepos, sortByTicket: state.sortByTicket)
	state.repositories = IdentifiedArrayOf(uniqueElements: sortedRepos)
}
