import ComposableArchitecture
import SwiftUI
import Settings
import TerminalFeature

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>

	/// Terminal session status keyed by repository path. O(1) lookup per row, built once by the parent.
	let statusByPath: [String: TerminalSessionStatus]

	/// Active branch-name query. Empty shows every row.
	var searchText: String = ""

	/// Repository paths with a live terminal session, or `nil` when the active-terminal filter is
	/// off. Built once by the parent.
	var livePaths: Set<String>?

	var body: some View {
		let isExpanded = Binding(
			get: { !store.isCollapsed },
			set: { newValue in
				if newValue != !store.isCollapsed {
					store.send(.toggleCollapse)
				}
			}
		)
		// Resolved here rather than by the parent so a keystroke invalidates each group's own body
		// instead of the whole list's.
		let visibility = store.state.rowVisibility(query: searchText, livePaths: livePaths)
		let hasVisibleWorktrees = store.worktrees.contains { visibility.includesWorktree(id: $0.id) }

		if !visibility.isHidden {
			Section(isExpanded: isExpanded) {
				ForEach(store.scope(\.worktrees, action: \.worktrees)) { rowStore in
					if visibility.includesWorktree(id: rowStore.id) {
						RepositoryRowView(
							store: rowStore,
							terminalSessionStatus: statusByPath[rowStore.path]
						)
						.padding(.leading, 20)
						.listRowInsets(EdgeInsets())
					}
				}
			} header: {
				RepositoryRowView(
					store: store.scope(\.header, action: \.header),
					terminalSessionStatus: statusByPath[store.header.path],
					isGroupCollapsed: store.isCollapsed,
					onToggleCollapse: hasVisibleWorktrees
						? { isExpanded.wrappedValue = !isExpanded.wrappedValue } : nil,
					onRemove: { store.send(.remove) },
					worktreeCount: store.worktrees.count
				)
			}
			.listSectionSeparator(.hidden)
		}
	}
}

#Preview {
	let mainRow = RepositoryRowReducer.State(
		path: "/projects/myapp",
		name: "myapp",
		branchName: "main",
		isWorktree: false
	)
	let worktreeRow = RepositoryRowReducer.State(
		path: "/worktrees/myapp-feature",
		name: "myapp-feature",
		branchName: "MOB-123_feature",
		isWorktree: true
	)
	List {
		RepoGroupView(
			store: Store(
				initialState: RepoGroupReducer.State(
					id: "/projects/myapp",
					isCollapsed: false,
					header: mainRow,
					worktrees: IdentifiedArrayOf(uniqueElements: [worktreeRow]),
					settings: RepoGroupSettings()
				),
				reducer: { RepoGroupReducer() }
			),
			statusByPath: [:]
		)
	}
	.listStyle(.plain)
}
