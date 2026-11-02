import AppUI
import ComposableArchitecture
import SwiftUI

struct DeleteWorktreeConfirmationView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeConfirmationReducer>

	var body: some View {
		VStack(spacing: 20) {
			Image(systemName: "trash")
				.scaledFont(size: 32)
				.foregroundStyle(.secondary)

			Text("Remove Worktree")
				.scaledFont(.title2)
				.fontWeight(.medium)

			Text(description)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Text(store.name)
				.scaledFont(.body, design: .monospaced)
				.multilineTextAlignment(.center)
				.padding(.horizontal)
				.padding(.vertical, 8)
				.background(Color.secondary.opacity(0.1))
				.cornerRadius(6)
				.frame(maxWidth: .infinity)

			Toggle(isOn: $store.forceRemoval) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Force removal")
						.scaledFont(.body)
					Text("Remove even if there are uncommitted changes")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.toggleStyle(.checkbox)
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal)

			Toggle(isOn: $store.deleteLocalBranch) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Delete local branch")
						.scaledFont(.body)
					Text("Also delete the checked-out branch, even if it is unmerged; the default branch is never deleted")
						.scaledFont(.caption)
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
				.buttonStyle(.scaledBordered)

				Button("Remove", role: .destructive) {
					store.send(.confirmTapped(
						forceRemoval: store.forceRemoval,
						deleteLocalBranch: store.deleteLocalBranch
					))
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.scaledBorderedProminent)
				.tint(.red)
			}
		}
		.padding(24)
		.frame(width: 400)
	}

	/// Names everything the removal deletes.
	private var description: String {
		let folders = store.deletesDerivedData
			? "Deletes the worktree's folder and its Xcode DerivedData."
			: "Deletes the worktree's folder."
		return folders + " The branch stays unless you delete it below."
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
