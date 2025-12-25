import ComposableArchitecture
import SwiftUI

// MARK: - Stash Button View

struct StashButtonView: View {
	let store: StoreOf<StashButtonReducer>

	var body: some View {
		if store.hasChanges {
			Button {
				store.send(.stashTapped)
			} label: {
				Label("Stash", systemImage: "tray.and.arrow.down")
			}
			.disabled(store.isProcessing)
		}

		if store.hasStash {
			Button {
				store.send(.stashPopTapped)
			} label: {
				Label("Stash Pop", systemImage: "tray.and.arrow.up")
			}
			.disabled(store.isProcessing)
		}
	}
}

#Preview {
	VStack(spacing: 20) {
		StashButtonView(
			store: Store(
				initialState: StashButtonReducer.State(
					repositoryPath: "/Users/test/projects/my-project",
					hasStash: false
				),
				reducer: {
					StashButtonReducer()
				}
			)
		)

		StashButtonView(
			store: Store(
				initialState: StashButtonReducer.State(
					repositoryPath: "/Users/test/projects/my-project",
					hasStash: true
				),
				reducer: {
					StashButtonReducer()
				}
			)
		)
	}
	.padding()
}
