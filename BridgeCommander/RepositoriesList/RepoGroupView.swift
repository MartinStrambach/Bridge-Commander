import ComposableArchitecture
import SwiftUI

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>
	let sessions: IdentifiedArrayOf<TerminalSession>

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
			ForEach(store.scope(state: \.worktrees, action: \.worktrees)) { rowStore in
				RepositoryRowView(
					store: rowStore,
					terminalSessionStatus: sessions.first(where: { $0.repositoryPath == rowStore.path })?.status
				)
				.padding(.leading, 20)
				.listRowInsets(EdgeInsets())
			}
		} header: {
			RepositoryRowView(
				store: store.scope(state: \.header, action: \.header),
				terminalSessionStatus: sessions.first(where: { $0.repositoryPath == store.header.path })?.status,
				isGroupCollapsed: store.isCollapsed,
				onToggleCollapse: store.worktrees.isEmpty ? nil : { isExpanded.wrappedValue = !isExpanded.wrappedValue },
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
			sessions: []
		)
	}
	.listStyle(.plain)
}
