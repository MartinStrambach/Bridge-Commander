import ComposableArchitecture
import SwiftUI

// MARK: - Tuist Button View

struct TuistButtonView: View {
	let store: StoreOf<TuistButtonReducer>

	var body: some View {
		Group {
			if let runningAction = store.runningAction {
				GitOperationProgressView(
					text: progressText(for: runningAction),
					color: .purple,
					helpText: progressHelpText(for: runningAction)
				)
			}
			else {
				Menu {
					Button {
						store.send(.generateTapped)
					} label: {
						Label("Generate", systemImage: "hammer")
					}

					Button {
						store.send(.installTapped)
					} label: {
						Label("Install", systemImage: "arrow.down.circle")
					}

					Button {
						store.send(.cacheTapped)
					} label: {
						Label("Cache", systemImage: "tray")
					}

					Button {
						store.send(.editTapped)
					} label: {
						Label("Edit", systemImage: "pencil")
					}
				} label: {
					Text("Tuist")
						.font(.system(size: 12))
				}
				.menuStyle(.borderlessButton)
			}
		}
		.fixedSize()
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}

	// MARK: - Helper Methods

	private func progressText(for action: TuistAction) -> String {
		switch action {
		case .generate:
			"Generating..."
		case .install:
			"Installing..."
		case .cache:
			"Caching..."
		case .edit:
			"Opening..."
		}
	}

	private func progressHelpText(for action: TuistAction) -> String {
		switch action {
		case .generate:
			"Generating Xcode project with Tuist..."
		case .install:
			"Installing Tuist dependencies..."
		case .cache:
			"Caching Tuist targets..."
		case .edit:
			"Opening Tuist project for editing..."
		}
	}
}

#Preview {
	TuistButtonView(
		store: Store(
			initialState: TuistButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				TuistButtonReducer()
			}
		)
	)
}
