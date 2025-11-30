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
		.alert(store: store.scope(state: \.$confirmationAlert, action: \.confirmationAlert))
		.alert(store: store.scope(state: \.$errorAlert, action: \.errorAlert))
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
