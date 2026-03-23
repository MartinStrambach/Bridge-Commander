import ComposableArchitecture
import SwiftUI

struct RepoGroupView: View {
	@Bindable var store: StoreOf<RepoGroupReducer>
	let sessions: IdentifiedArrayOf<TerminalSession>

	var body: some View {
		// TCA's @ObservableState generates dynamic member lookup, so rowStore.isWorktree
		// and rowStore.path are valid reads within the ForEach observation context.
		ForEach(store.scope(state: \.rows, action: \.rows)) { rowStore in
			let isHeader = !rowStore.isWorktree

			if isHeader || !store.isCollapsed {
				RepositoryRowView(
					store: rowStore,
					terminalSessionStatus: sessions.first(where: { $0.repositoryPath == rowStore.path })?.status,
					isGroupCollapsed: isHeader ? store.isCollapsed : nil,
					onToggleCollapse: isHeader ? { withAnimation(.easeInOut(duration: 0.2)) { store.send(.toggleCollapse) } } : nil,
					onRemove: isHeader ? { store.send(.remove) } : nil
				)
				.padding(.leading, isHeader ? 0 : 20)
				.transition(.asymmetric(
					insertion: .move(edge: .top).combined(with: .opacity),
					removal: .move(edge: .top).combined(with: .opacity)
				))
			}
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
