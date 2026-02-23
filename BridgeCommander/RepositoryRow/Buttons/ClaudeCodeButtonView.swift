import ComposableArchitecture
import SwiftUI

// MARK: - Claude Code Button View

struct ClaudeCodeButtonView: View {
	@Bindable
	var store: StoreOf<ClaudeCodeButtonReducer>

	private var buttonTooltip: String {
		if store.isLaunching {
			"Launching Claude Code..."
		}
		else {
			"Launch Claude Code in repository"
		}
	}

	var body: some View {
		ToolButton(
			label: store.isLaunching ? "Launching" : "Claude Code",
			icon: .systemImage("sparkles"),
			tooltip: buttonTooltip,
			isProcessing: store.isLaunching,
			tint: store.isLaunching ? .purple : nil,
			action: { store.send(.launchClaudeCodeButtonTapped) }
		)
		.alert($store.scope(state: \.alert, action: \.alert))
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
}
