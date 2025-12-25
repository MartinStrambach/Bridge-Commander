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
				ActionButton(
					icon: .systemImage("trash"),
					tooltip: "Remove worktree",
					color: .red,
					action: { store.send(.showConfirmation) }
				)
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
