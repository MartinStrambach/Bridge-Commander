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
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}

	// MARK: - Computed Properties

	private var buttonTooltip: String {
		if store.isLaunching {
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
