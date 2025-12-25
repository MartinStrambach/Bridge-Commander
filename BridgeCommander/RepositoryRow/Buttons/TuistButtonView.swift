import ComposableArchitecture
import SwiftUI

// MARK: - Tuist Button View

struct TuistButtonView: View {
	let store: StoreOf<TuistButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

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
				} label: {
					ToolButton(
						label: abbreviationMode.isAbbreviated ? "Tst" : "Tuist",
						icon: .systemImage("cube.box"),
						tooltip: "Tuist actions",
						isProcessing: false,
						tint: .purple,
						action: {}
					)
					.environmentObject(abbreviationMode)
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
			return "Generating..."
		case .install:
			return "Installing..."
		case .cache:
			return "Caching..."
		}
	}

	private func progressHelpText(for action: TuistAction) -> String {
		switch action {
		case .generate:
			return "Generating Xcode project with Tuist..."
		case .install:
			return "Installing Tuist dependencies..."
		case .cache:
			return "Caching Tuist targets..."
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
	.environmentObject(AbbreviationMode())
}
