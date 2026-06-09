import ComposableArchitecture
import SwiftUI
import Settings
import TerminalFeature

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>

	/// Terminal session status keyed by repository path. O(1) lookup per row, built once by the parent.
	let statusByPath: [String: TerminalSessionStatus]

	var body: some View {
		let isExpanded = Binding(
			get: { !store.isCollapsed },
			set: { newValue in
				if newValue != !store.isCollapsed {
					store.send(.toggleCollapse)
				}
			}
		)

		Section(isExpanded: isExpanded) {
			ForEach(store.scope(\.worktrees, action: \.worktrees)) { rowStore in
				RepositoryRowView(
					store: rowStore,
					terminalSessionStatus: statusByPath[rowStore.path]
				)
				.padding(.leading, 20)
				.listRowInsets(EdgeInsets())
			}
		} header: {
			RepositoryRowView(
				store: store.scope(\.header, action: \.header),
				terminalSessionStatus: statusByPath[store.header.path],
				isGroupCollapsed: store.isCollapsed,
				onToggleCollapse: store.worktrees
					.isEmpty ? nil : { isExpanded.wrappedValue = !isExpanded.wrappedValue },
				onRemove: { store.send(.remove) }
			)
		}
		.listSectionSeparator(.hidden)
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
