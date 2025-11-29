import ComposableArchitecture
import SwiftUI

// MARK: - Claude Code Button View

struct ClaudeCodeButtonView: View {
	let store: StoreOf<ClaudeCodeButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		ToolButton(
			label: store.isLaunching
				? (abbreviationMode.isAbbreviated ? "Launch" : "Launching")
				: (abbreviationMode.isAbbreviated ? "CC" : "Claude Code"),
			icon: .systemImage("sparkles"),
			tooltip: buttonTooltip,
			isProcessing: store.isLaunching,
			tint: store.isLaunching ? .purple : nil,
			action: { store.send(.launchClaudeCodeButtonTapped) }
		)
		.environmentObject(abbreviationMode)
		.alert("Failed to Launch Claude Code", isPresented: .constant(store.errorMessage != nil)) {
			Button("OK") {
				store.send(.dismissError)
			}
		} message: {
			if let errorMessage = store.errorMessage {
				Text(errorMessage)
			}
		}
	}

	// MARK: - Computed Properties

	private var buttonTooltip: String {
		if let errorMessage = store.errorMessage {
			"Error: \(errorMessage)"
		}
		else if store.isLaunching {
			"Launching Claude Code..."
		}
		else {
			"Launch Claude Code in repository"
		}
	}
}

#Preview {
	ClaudeCodeButtonView(
		store: Store(
			initialState: ClaudeCodeButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				ClaudeCodeButtonReducer()
			}
		)
	)
	.environmentObject(AbbreviationMode())
}
