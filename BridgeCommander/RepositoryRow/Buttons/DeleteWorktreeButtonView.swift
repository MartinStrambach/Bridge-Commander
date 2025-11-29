import ComposableArchitecture
import SwiftUI

struct DeleteWorktreeButtonView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeButtonReducer>

	var body: some View {
		Group {
			if store.isRemoving {
				ProgressView()
					.scaleEffect(0.5)
			}
			else {
				Button(action: { store.send(.showConfirmation) }) {
					Image(systemName: "trash")
						.foregroundColor(.red)
				}
				.buttonStyle(.plain)
				.help("Remove worktree")
			}
		}
		.alert("Remove Worktree", isPresented: $store.showRemoveConfirmation) {
			Button("Cancel", role: .cancel) { store.send(.cancelRemoval) }
			Button("Remove", role: .destructive) { store.send(.confirmRemoval) }
		} message: {
			Text("Are you sure you want to remove this worktree?\n\n\(store.name)")
		}
		.alert("Removal Error", isPresented: .constant(store.removalError != nil)) {
			Button("OK") { store.removalError = nil }
		} message: {
			if let error = store.removalError {
				Text(error)
			}
		}
	}
}

#Preview {
	DeleteWorktreeButtonView(
		store: Store(
			initialState: DeleteWorktreeButtonReducer.State(
				name: "worktree",
				path: "/path/to/worktree"
			),
			reducer: {
				DeleteWorktreeButtonReducer()
			}
		)
	)
}
