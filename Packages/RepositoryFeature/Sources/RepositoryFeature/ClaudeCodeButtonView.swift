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

/// The Claude Code button as an entry of another menu (the repository row's "⋯" menu).
///
/// A menu entry cannot present anything, so whoever shows this must also apply
/// `claudeCodePresentations(store:)` to a view outside the menu.
struct ClaudeCodeMenuItem: View {
	let store: StoreOf<ClaudeCodeButtonReducer>

	var body: some View {
		Button {
			store.send(.launchClaudeCodeButtonTapped)
		} label: {
			Label(store.isLaunching ? "Launching Claude Code..." : "Launch Claude Code", systemImage: "sparkles")
		}
		.disabled(store.isLaunching)
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
