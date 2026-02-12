import ComposableArchitecture
import SwiftUI

// MARK: - Dialog View

struct CreateWorktreeDialogView: View {
	@Bindable
	var store: StoreOf<CreateWorktreeButtonReducer>

	var body: some View {
		VStack(spacing: 20) {
			Text("Create New Worktree")
				.font(.headline)

			VStack(alignment: .leading, spacing: 12) {
				Text("Base Branch")
					.font(.subheadline)
					.foregroundColor(.secondary)

				if store.isLoadingBranches {
					ProgressView()
						.scaleEffect(0.7)
						.frame(maxWidth: .infinity)
				}
				else {
					Picker("Branch name", selection: $store.selectedBaseBranch) {
						ForEach(store.availableBranches, id: \.self) { branchInfo in
							Text(branchInfo.name + (branchInfo.isRemoteOnly ? " (remote)" : ""))
								.foregroundColor(branchInfo.isRemoteOnly ? .orange.opacity(0.5) : .green.opacity(0.8))
								.tag(branchInfo.name)
						}
					}
					.pickerStyle(.menu)
					.disabled(store.availableBranches.isEmpty)
				}

				Text("New Branch Name")
					.font(.subheadline)
					.foregroundColor(.secondary)

				TextField("Enter branch name", text: $store.branchName)
					.textFieldStyle(.roundedBorder)
			}
			.padding()

			HStack {
				Button("Cancel") {
					store.send(.cancelCreation)
				}
				.keyboardShortcut(.cancelAction)

				Spacer()

				Button("Create") {
					store.send(.confirmCreation)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(store.branchName.isEmpty || store.availableBranches.isEmpty)
			}
			.padding()
		}
		.frame(width: 400)
		.padding()
	}
}

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
				ActionButton(
					icon: .systemImage("plus.square.on.square"),
					tooltip: "Create new worktree",
					color: .green,
					action: { store.send(.showDialog) }
				)
			}
		}
		.sheet(isPresented: $store.showCreateDialog) {
			CreateWorktreeDialogView(store: store)
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
