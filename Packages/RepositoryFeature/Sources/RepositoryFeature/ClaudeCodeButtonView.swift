import ComposableArchitecture
import SwiftUI
import AppUI

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
		.alert($store.scope(\.$alert, action: \.alert))
	}

}

extension Store where State == ClaudeCodeButtonReducer.State, Action == ClaudeCodeButtonReducer.Action {
	/// The button as an entry of the repository row's "⋯" menu.
	var menuEntry: PopUpMenuAction {
		PopUpMenuAction(
			self.isLaunching ? "Launching Claude Code..." : "Launch Claude Code",
			systemImage: "sparkles",
			isEnabled: !self.isLaunching
		) {
			self.send(.launchClaudeCodeButtonTapped)
		}
	}
}

extension View {
	/// The Claude Code button's error alert, for a `ClaudeCodeMenuItem`.
	func claudeCodePresentations(store: StoreOf<ClaudeCodeButtonReducer>) -> some View {
		modifier(ClaudeCodePresentations(store: store))
	}
}

private struct ClaudeCodePresentations: ViewModifier {
	@Bindable
	var store: StoreOf<ClaudeCodeButtonReducer>

	func body(content: Content) -> some View {
		content.alert($store.scope(\.$alert, action: \.alert))
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
