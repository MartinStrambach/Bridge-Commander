import ComposableArchitecture
import SwiftUI

// MARK: - Terminal Button View

struct TerminalButtonView: View {
	let store: StoreOf<TerminalButtonReducer>

	@Shared(.isAbbreviated)
	private var isAbbreviated = false

	var body: some View {
		ToolButton(
			label: isAbbreviated ? "Term" : "Terminal",
			icon: .systemImage("terminal"),
			tooltip: "Open terminal at repository location",
			action: { store.send(.openTerminalButtonTapped) }
		)
	}
}

#Preview {
	TerminalButtonView(
		store: Store(
			initialState: TerminalButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				TerminalButtonReducer()
			}
		)
	)
}
