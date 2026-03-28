import ComposableArchitecture
import Foundation

@Reducer
struct RepoGroupReducer {
	@ObservableState
	struct State: Equatable, Identifiable {
		/// Normalized root repo path — used as the unique ID.
		let id: String
		var isCollapsed: Bool
		/// The main (non-worktree) repository row.
		var header: RepositoryRowReducer.State
		/// Worktree rows, sorted by the active sortMode.
		var worktrees: IdentifiedArrayOf<RepositoryRowReducer.State>
		var settings: RepoGroupSettings
	}

	enum Action {
		/// Flips isCollapsed. RepositoryListReducer intercepts this to persist the change.
		case toggleCollapse
		/// Signals intent to remove this group. RepositoryListReducer intercepts and handles removal.
		case remove
		/// Delegates to the header row reducer.
		case header(RepositoryRowReducer.Action)
		/// Delegates to child worktree row reducers.
		case worktrees(IdentifiedActionOf<RepositoryRowReducer>)
	}

	var body: some Reducer<State, Action> {
		Scope(state: \.header, action: \.header) {
			RepositoryRowReducer()
		}
		Reduce { state, action in
			switch action {
			case .toggleCollapse:
				state.isCollapsed.toggle()
				return .none

			case .header,
			     .remove,
			     .worktrees:
				return .none
			}
		}
		.forEach(\.worktrees, action: \.worktrees) {
			RepositoryRowReducer()
		}
	}
}
