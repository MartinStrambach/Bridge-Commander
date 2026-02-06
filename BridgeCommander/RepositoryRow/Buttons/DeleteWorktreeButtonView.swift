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
		.sheet(isPresented: $store.showingConfirmationSheet) {
			DeleteWorktreeConfirmationView(store: store)
		}
		.alert(store: store.scope(state: \.$errorAlert, action: \.errorAlert))
	}
}

private struct DeleteWorktreeConfirmationView: View {
	@Bindable
	var store: StoreOf<DeleteWorktreeButtonReducer>

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
				.lineLimit(1)
				.padding(.horizontal)
				.padding(.vertical, 8)
				.background(Color.secondary.opacity(0.1))
				.cornerRadius(6)
				.fixedSize(horizontal: true, vertical: false)
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

			HStack(spacing: 12) {
				Button("Cancel") {
					store.send(.cancelRemoval)
				}
				.keyboardShortcut(.cancelAction)
				.buttonStyle(.bordered)

				Button("Remove", role: .destructive) {
					store.send(.confirmRemoval)
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
				path: "/path/to/worktree"
			),
			reducer: {
				DeleteWorktreeButtonReducer()
			}
		)
	)
}
