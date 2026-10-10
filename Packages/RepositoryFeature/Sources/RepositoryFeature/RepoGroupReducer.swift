import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature

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
		/// A scan's rows, merged into the loaded ones. Done here rather than by the list writing
		/// `worktrees`: only a change made in this reducer lets `forEach` cancel the effects of the
		/// rows the scan dropped.
		case applyScannedRows([ScannedRepository], sortMode: SortMode, settings: RepoGroupSettings)
		/// Delegates to the header row reducer.
		case header(RepositoryRowReducer.Action)
		/// Delegates to child worktree row reducers.
		case worktrees(IdentifiedActionOf<RepositoryRowReducer>)
	}

	var body: some Reducer<State, Action> {
		Scope(\.header, action: \.header) {
			RepositoryRowReducer()
		}
		Reduce { state, action in
			switch action {
			case .toggleCollapse:
				state.isCollapsed.toggle()
				return .none

			case let .applyScannedRows(scanned, sortMode, settings):
				mergeGroupRows(into: &state, scanned: scanned, sortMode: sortMode, rowSettings: settings)
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
