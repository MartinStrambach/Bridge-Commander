import ComposableArchitecture
import SwiftUI

// MARK: - Git Actions Menu View

struct GitActionsMenuView: View {
	let store: StoreOf<GitActionsMenuReducer>

	var body: some View {
		Group {
			if store.fetchButton.isFetching {
				GitOperationProgressView(
					text: "Fetching...",
					color: .cyan,
					helpText: "Fetching updates from remote..."
				)
			}
			else if store.pullButton.isPulling {
				GitOperationProgressView(
					text: "Pulling...",
					color: .blue,
					helpText: "Pulling changes from remote..."
				)
			}
			else if store.pushButton.isPushing {
				GitOperationProgressView(
					text: "Pushing...",
					color: .green,
					helpText: "Pushing commits to remote..."
				)
			}
			else if store.mergeMasterButton.isMergingMaster {
				GitOperationProgressView(
					text: "Merging...",
					color: .orange,
					helpText: "Merging master branch..."
				)
			}
			else if store.abortMergeButton.isAbortingMerge {
				GitOperationProgressView(
					text: "Aborting...",
					color: .red,
					helpText: "Aborting merge..."
				)
			}
			else if store.stashButton.isProcessing {
				GitOperationProgressView(
					text: store.stashButton.hasStash ? "Popping stash..." : "Stashing...",
					color: .purple,
					helpText: store.stashButton.hasStash ? "Restoring stashed changes..." : "Stashing changes..."
				)
			}
			else {
				Menu {
					if store.isMergeInProgress {
						AbortMergeButtonView(store: store.scope(state: \.abortMergeButton, action: \.abortMergeButton))
					}

					if store.hasRemoteBranch {
						FetchButtonView(store: store.scope(state: \.fetchButton, action: \.fetchButton))
						PullButtonView(store: store.scope(state: \.pullButton, action: \.pullButton))
					}

					if store.unpushedCommitsCount > 0 || !store.hasRemoteBranch {
						PushButtonView(store: store.scope(state: \.pushButton, action: \.pushButton))
					}

					if !store.isMergeInProgress {
						StashButtonView(store: store.scope(state: \.stashButton, action: \.stashButton))
					}

					if store.currentBranch != "master", store.currentBranch != "main", !store.isMergeInProgress {
						MergeMasterButtonView(store: store.scope(
							state: \.mergeMasterButton,
							action: \.mergeMasterButton
						))
					}
				} label: {
					Text("Git Actions")
						.font(.system(size: 12))
				}
				.menuStyle(.borderlessButton)
				.help("Quick Git Actions")
			}
		}
		.fixedSize()
		.scrollableAlert(store.fetchButton.alert)
		.scrollableAlert(store.pullButton.alert)
		.scrollableAlert(store.pushButton.alert)
		.scrollableAlert(store.mergeMasterButton.alert)
		.scrollableAlert(store.abortMergeButton.alert)
		.scrollableAlert(store.stashButton.alert)
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
