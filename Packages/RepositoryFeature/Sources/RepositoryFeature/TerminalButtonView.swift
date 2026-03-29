import ComposableArchitecture
import SwiftUI
import AppUI

// MARK: - Terminal Button View

struct TerminalButtonView: View {
	let store: StoreOf<TerminalButtonReducer>

	var body: some View {
		ActionButton(
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
