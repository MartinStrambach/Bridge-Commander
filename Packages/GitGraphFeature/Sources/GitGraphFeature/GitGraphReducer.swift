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

		/// The commit whose diff is open in the bottom pane, or nil when none is selected.
		///
		/// Held separately from `commitDetail` so a row only has to observe this one property:
		/// reading the hash off the child state instead would re-render every visible row each
		/// time the child loaded a file list or a diff.
		var selectedCommitHash: String?

		var commitDetail: CommitDetailReducer.State?

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
		case commitTapped(String)
		case closeDetailButtonTapped
		case commitDetail(CommitDetailReducer.Action)
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

				// A reload can drop the selected commit (a rewritten branch, a narrower limit).
				// A commit that is still listed keeps its open diff: its content cannot change.
				if let selected = state.selectedCommitHash, !commits.contains(where: { $0.hash == selected }) {
					state.selectedCommitHash = nil
					state.commitDetail = nil
				}
				return .none

			case let .loadFailed(message):
				state.isLoading = false
				state.errorMessage = message
				return .none

			case let .commitTapped(hash):
				guard
					state.selectedCommitHash != hash,
					let commit = state.rows.first(where: { $0.commit.hash == hash })?.commit
				else {
					return .none
				}

				state.selectedCommitHash = hash
				state.commitDetail = CommitDetailReducer.State(
					repositoryPath: state.repositoryPath,
					commit: commit
				)
				// Driven from here rather than the view's `.task`, so re-selecting always loads
				// even when SwiftUI reuses the pane for the new commit.
				return .send(.commitDetail(.task))

			case .closeDetailButtonTapped:
				state.selectedCommitHash = nil
				state.commitDetail = nil
				return .none

			case .commitDetail:
				return .none
			}
		}
		.ifLet(\.commitDetail, action: \.commitDetail) {
			CommitDetailReducer()
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
