import ComposableArchitecture
import SwiftUI

struct CreateWorktreeButtonView: View {
	@Bindable
	var store: StoreOf<CreateWorktreeButtonReducer>

	var body: some View {
		Group {
			if store.isCreating {
				ProgressView()
					.scaleEffect(0.5)
			}
			else {
				Button(action: { store.send(.showDialog) }) {
					Image(systemName: "plus.square.on.square")
						.foregroundColor(.green)
				}
				.buttonStyle(.plain)
				.help("Create new worktree")
			}
		}
		.alert("Create New Worktree", isPresented: $store.showCreateDialog) {
			TextField("Branch name", text: $store.branchName)
			Button("Cancel", role: .cancel) { store.send(.cancelCreation) }
			Button("Create") { store.send(.confirmCreation) }
				.disabled(store.branchName.isEmpty)
		} message: {
			Text("Enter the name for the new worktree branch")
		}
		.alert(store: store.scope(state: \.$errorAlert, action: \.errorAlert))
	}
}

#Preview {
	CreateWorktreeButtonView(
		store: Store(
			initialState: CreateWorktreeButtonReducer.State(
				repositoryPath: "/path/to/repository"
			),
			reducer: {
				CreateWorktreeButtonReducer()
			}
		)
	)
}
