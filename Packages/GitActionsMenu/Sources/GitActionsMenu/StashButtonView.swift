import ComposableArchitecture
import GitCore
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
			// Restoring the work and keeping the entry are separate decisions, so each
			// combination gets its own item: apply restores and keeps, pop restores and
			// drops, clear only drops. Clear confirms first — see StashButtonReducer.
			Button {
				store.send(.stashApplyTapped)
			} label: {
				Label("Apply Stash", systemImage: "tray.and.arrow.up")
			}
			.disabled(store.isProcessing)

			Button {
				store.send(.stashPopTapped)
			} label: {
				Label("Pop Stash", systemImage: "tray.and.arrow.up.fill")
			}
			.disabled(store.isProcessing)

			Button(role: .destructive) {
				store.send(.stashClearTapped)
			} label: {
				Label("Clear Stash", systemImage: "trash")
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
					currentBranch: "branch"
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
					currentBranch: "branch",
					stash: GitStashEntry(
						reference: "stash@{0}",
						branch: "branch",
						message: "abc1234 Some work in progress"
					)
				),
				reducer: {
					StashButtonReducer()
				}
			)
		)
	}
	.padding()
}
