import ComposableArchitecture
import SwiftUI

// MARK: - Terminal Button View

struct TerminalButtonView: View {
	let store: StoreOf<TerminalButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		ToolButton(
			label: abbreviationMode.isAbbreviated ? "Term" : "Terminal",
			icon: .systemImage("terminal"),
			tooltip: "Open terminal at repository location",
			action: { store.send(.openTerminalButtonTapped) }
		)
		.environmentObject(abbreviationMode)
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
	.environmentObject(AbbreviationMode())
}
