import ComposableArchitecture
import Foundation
import GitCore

@Reducer
public struct GitGraphReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		let repositoryName: String
		var rows: [GitGraphRow] = []
		var isLoading = false
		var errorMessage: String?
		var commitLimit = 300

		/// True when the last load filled the limit, so older commits likely exist
		var canLoadMore = false

		public init(repositoryPath: String, repositoryName: String) {
			self.repositoryPath = repositoryPath
			self.repositoryName = repositoryName
		}
	}

	public enum Action {
		case task
		case refreshButtonTapped
		case loadMoreButtonTapped
		case closeButtonTapped
		case commitsLoaded([GitLogCommit])
		case loadFailed(String)
	}

	private nonisolated enum CancellableId: Hashable {
		case loadCommits
	}

	@Dependency(\.dismiss)
	private var dismiss

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task, .refreshButtonTapped:
				return loadCommits(state: &state)

			case .loadMoreButtonTapped:
				state.commitLimit += 300
				return loadCommits(state: &state)

			case .closeButtonTapped:
				return .run { [dismiss] _ in await dismiss() }

			case let .commitsLoaded(commits):
				state.isLoading = false
				state.errorMessage = nil
				state.canLoadMore = commits.count >= state.commitLimit
				state.rows = GitGraphLayout.layout(commits: commits)
				return .none

			case let .loadFailed(message):
				state.isLoading = false
				state.errorMessage = message
				return .none
			}
		}
	}

	private func loadCommits(state: inout State) -> Effect<Action> {
		state.isLoading = true
		return .run { [path = state.repositoryPath, limit = state.commitLimit] send in
			do {
				let commits = try await GitLogHelper.loadCommits(at: path, limit: limit)
				await send(.commitsLoaded(commits))
			}
			catch {
				await send(.loadFailed(error.localizedDescription))
			}
		}
		.cancellable(id: CancellableId.loadCommits, cancelInFlight: true)
	}
}
