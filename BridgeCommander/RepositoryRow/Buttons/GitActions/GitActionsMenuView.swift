import ComposableArchitecture
import SwiftUI

// MARK: - Git Actions Menu View

struct GitActionsMenuView: View {
	let store: StoreOf<GitActionsMenuReducer>

	var body: some View {
		Menu {
			if store.hasRemoteBranch {
				PullButtonView(store: store.scope(state: \.pullButton, action: \.pullButton))
			}

			if store.currentBranch != "master", store.currentBranch != "main", !store.isMergeInProgress {
				MergeMasterButtonView(store: store.scope(state: \.mergeMasterButton, action: \.mergeMasterButton))
			}
		} label: {
			Text("Git Actions")
				.font(.system(size: 12))
		}
		.menuStyle(.borderlessButton)
		.help("Quick Git Actions")
		.fixedSize()
		.task {
			store.send(.onAppear)
		}
	}
}

#Preview("Idle") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				currentBranch: "feature/test"
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}

#Preview("On Master") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				currentBranch: "master"
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}
