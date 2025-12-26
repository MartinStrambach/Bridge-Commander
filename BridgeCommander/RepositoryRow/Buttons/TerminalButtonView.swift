import ComposableArchitecture
import SwiftUI

// MARK: - Terminal Button View

struct TerminalButtonView: View {
	let store: StoreOf<TerminalButtonReducer>

	var body: some View {
		ToolButton(
			label: "Terminal",
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
