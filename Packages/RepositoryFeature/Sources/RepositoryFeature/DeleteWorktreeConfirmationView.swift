import ComposableArchitecture
import SwiftUI

struct DeleteWorktreeConfirmationView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeConfirmationReducer>

	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 48))
				.foregroundStyle(.orange)

			Text("Remove Worktree")
				.font(.title2)
				.bold()

			Text("Are you sure you want to remove this worktree?")
				.multilineTextAlignment(.center)

			Text(store.name)
				.font(.system(.body, design: .monospaced))
				.multilineTextAlignment(.center)
				.padding(.horizontal)
				.padding(.vertical, 8)
				.background(Color.secondary.opacity(0.1))
				.cornerRadius(6)
				.frame(maxWidth: .infinity)

			Toggle(isOn: $store.forceRemoval) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Force removal")
						.font(.body)
					Text("Remove even if there are uncommitted changes")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.toggleStyle(.checkbox)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)

			Toggle(isOn: $store.deleteLocalBranch) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Delete local branch")
						.font(.body)
					Text("Also delete the checked-out branch, even if it is unmerged; the default branch is never deleted")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.toggleStyle(.checkbox)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)

			HStack(spacing: 12) {
				Button("Cancel") {
					store.send(.cancelTapped)
				}
				.keyboardShortcut(.cancelAction)
				.buttonStyle(.bordered)

				Button("Remove", role: .destructive) {
					store.send(.confirmTapped(
						forceRemoval: store.forceRemoval,
						deleteLocalBranch: store.deleteLocalBranch
					))
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
				.tint(.red)
			}
		}
		.padding(24)
		.frame(width: 400)
	}
}

#Preview {
	DeleteWorktreeButtonView(
		store: Store(
			initialState: DeleteWorktreeButtonReducer.State(
				name: "worktree",
				path: "/path/to/worktree",
				defaultBranch: ""
			),
			reducer: {
				DeleteWorktreeButtonReducer()
			}
		)
	)
}
