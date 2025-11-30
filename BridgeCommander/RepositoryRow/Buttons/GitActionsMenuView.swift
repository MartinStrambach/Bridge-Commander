import ComposableArchitecture
import SwiftUI

// MARK: - Git Actions Menu View

struct GitActionsMenuView: View {
	let store: StoreOf<GitActionsMenuReducer>

	var body: some View {
		Group {
			if store.isMergingMaster {
				// Show progress indicator when merge is in progress
				HStack(spacing: 6) {
					ProgressView()
						.controlSize(.small)
						.scaleEffect(0.8)
					Text("Merging...")
						.font(.caption)
						.foregroundColor(.secondary)
				}
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.background(Color.orange.opacity(0.1))
				.cornerRadius(6)
				.help("Merging master branch...")
			}
			else {
				Menu {
					Button {
						store.send(.mergeMasterTapped)
					} label: {
						Label("Merge Master", systemImage: "arrow.triangle.merge")
					}
				} label: {
					Image(systemName: "ellipsis.circle")
						.font(.system(size: 16))
				}
				.menuStyle(.borderlessButton)
				.help("Quick Git Actions")
			}
		}
		.fixedSize()
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}
}

#Preview("Idle") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}

#Preview("Merging") {
	GitActionsMenuView(
		store: Store(
			initialState: GitActionsMenuReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				isMergingMaster: true
			),
			reducer: {
				GitActionsMenuReducer()
			}
		)
	)
	.padding()
}
