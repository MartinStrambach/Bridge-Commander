import ComposableArchitecture
import Foundation

@Reducer
struct RepoGroupReducer {
	@ObservableState
	struct State: Equatable, Identifiable {
		/// Normalized root repo path — used as the unique ID.
		let id: String
		var isCollapsed: Bool
		/// rows[0] is always the main repo (isWorktree == false).
		/// rows[1...] are worktrees, sorted by the active sortMode.
		var rows: IdentifiedArrayOf<RepositoryRowReducer.State>
	}

	enum Action {
		/// Flips isCollapsed. RepositoryListReducer intercepts this to persist the change.
		case toggleCollapse
		/// Signals intent to remove this group. RepositoryListReducer intercepts and handles removal.
		case remove
		/// Delegates to child row reducers.
		case rows(IdentifiedActionOf<RepositoryRowReducer>)
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .toggleCollapse:
				state.isCollapsed.toggle()
				return .none
			case .remove:
				// Handled by parent RepositoryListReducer via the intercept pattern
				return .none
			case .rows:
				// Handled by .forEach below; explicit case required by exhaustive switch
				return .none
			}
		}
		.forEach(\.rows, action: \.rows) {
			RepositoryRowReducer()
		}
	}
}
