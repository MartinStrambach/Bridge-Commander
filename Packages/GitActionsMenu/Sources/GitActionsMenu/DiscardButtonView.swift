import ComposableArchitecture
import SwiftUI

// MARK: - Discard Button View

/// Renders up to two destructive menu items. Each only dispatches a tap action;
/// the confirmation dialog itself is presented at the GitActionsMenuView root,
/// because dialogs attached to buttons inside a macOS `Menu` do not present reliably.
struct DiscardButtonView: View {
	let store: StoreOf<DiscardButtonReducer>

	var body: some View {
		if store.hasTrackedChanges {
			Button(role: .destructive) {
				store.send(.discardTrackedTapped)
			} label: {
				Label("Discard Tracked Changes", systemImage: "arrow.uturn.backward")
			}
			.disabled(store.isProcessing)
		}

		if store.hasUntrackedFiles {
			Button(role: .destructive) {
				store.send(.discardAllTapped)
			} label: {
				Label("Discard All Changes", systemImage: "trash")
			}
			.disabled(store.isProcessing)
		}
	}
}

#Preview {
	VStack(spacing: 20) {
		DiscardButtonView(
			store: Store(
				initialState: DiscardButtonReducer.State(
					repositoryPath: "/Users/test/projects/my-project"
				),
				reducer: {
					DiscardButtonReducer()
				}
			)
		)

		DiscardButtonView(
			store: Store(
				initialState: {
					var state = DiscardButtonReducer.State(
						repositoryPath: "/Users/test/projects/my-project"
					)
					state.hasTrackedChanges = true
					state.hasUntrackedFiles = true
					return state
				}(),
				reducer: {
					DiscardButtonReducer()
				}
			)
		)
	}
	.padding()
}
