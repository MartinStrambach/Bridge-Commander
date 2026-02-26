import ComposableArchitecture
import SwiftUI

struct CommitView: View {
	@Bindable
	var store: StoreOf<CommitReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Commit Staged Changes")
				.font(.headline)

			TextEditor(text: $store.message)
				.font(.body)
				.frame(height: 120)
				.overlay(
					RoundedRectangle(cornerRadius: 6)
						.stroke(Color(NSColor.separatorColor), lineWidth: 1)
				)
				.overlay(alignment: .topLeading) {
					if store.message.isEmpty {
						Text("Commit message")
							.foregroundStyle(.secondary)
							.padding(.horizontal, 6)
							.padding(.vertical, 8)
							.allowsHitTesting(false)
					}
				}

			HStack {
				Spacer()
				Button("Cancel") {
					store.send(.cancelTapped)
				}
				.keyboardShortcut(.cancelAction)
				.disabled(store.isCommitting)

				if store.isCommitting {
					ProgressView()
						.scaleEffect(0.7)
				}
				else {
					Button("Commit") {
						store.send(.commitTapped)
					}
					.keyboardShortcut(.defaultAction)
					.disabled(store.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			}
		}
		.padding(24)
		.frame(width: 450)
		.sheet(item: $store.scope(state: \.alert, action: \.alert)) { alertStore in
			ScrollableAlertView(store: alertStore)
		}
	}
}

#Preview {
	CommitView(
		store: Store(
			initialState: CommitReducer.State(repositoryPath: "/Users/test/repo")
		) {
			CommitReducer()
		}
	)
}
