import ComposableArchitecture
import SwiftUI

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>
	let sessions: IdentifiedArrayOf<TerminalSession>

	var body: some View {
		Section {
			ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
				if rowStore.isWorktree {
					RepositoryRowView(
						store: rowStore,
						terminalSessionStatus: sessions.first(where: { $0.repositoryPath == rowStore.path })?.status
					)
					.padding(.leading, 20)
					.listRowInsets(EdgeInsets())
					.listRowSeparator(.hidden)
				}
			}
		} header: {
			ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
				if !rowStore.isWorktree {
					RepositoryRowView(
						store: rowStore,
						terminalSessionStatus: sessions.first(where: { $0.repositoryPath == rowStore.path })?.status,
						isGroupCollapsed: store.isCollapsed,
						onToggleCollapse: { withAnimation(.easeInOut(duration: 0.2)) { _ = store.send(.toggleCollapse) } },
						onRemove: { store.send(.remove) }
					)
				}
			}
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
					rows: IdentifiedArrayOf(uniqueElements: [mainRow, worktreeRow])
				),
				reducer: { RepoGroupReducer() }
			),
			sessions: []
		)
	}
	.listStyle(.plain)
}
