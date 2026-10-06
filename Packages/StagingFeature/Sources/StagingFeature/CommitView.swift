import ComposableArchitecture
import SwiftUI
import AppUI

struct CommitView: View {
	@Bindable
	var store: StoreOf<CommitReducer>

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Commit Staged Changes")
				.scaledFont(.headline)

			TextEditor(text: $store.message)
				.scaledFont(.body)
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
				.buttonStyle(.scaledAutomatic)
				.keyboardShortcut(.cancelAction)
				.disabled(store.isCommitting)

				Button("Commit & Push") {
					store.send(.commitAndPushTapped)
				}
				.buttonStyle(.scaledAutomatic)
				.disabled(store.isCommitting || store.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				.overlay {
					if store.isCommitting && store.shouldPushAfterCommit {
						ProgressView()
							.scaleEffect(0.35)
					}
				}

				Button("Commit") {
					store.send(.commitTapped)
				}
				.buttonStyle(.scaledAutomatic)
				.keyboardShortcut(.defaultAction)
				.disabled(store.isCommitting || store.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				.overlay {
					if store.isCommitting && !store.shouldPushAfterCommit {
						ProgressView()
							.scaleEffect(0.35)
					}
				}
			}
		}
		.padding(24)
		.frame(width: 450)
		.sheet(item: $store.scope(\.$alert, action: \.alert)) { alertStore in
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
