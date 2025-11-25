import ComposableArchitecture
import SwiftUI

// MARK: - Terminal Button View

struct TerminalButtonView: View {
	let store: StoreOf<TerminalButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		Button(action: { store.send(.openTerminalButtonTapped) }) {
			Label(buttonLabel, systemImage: "terminal")
				.frame(minWidth: abbreviationMode.isAbbreviated ? 50 : 120)
		}
		.buttonStyle(.bordered)
		.fixedSize(horizontal: true, vertical: false)
		.help("Open terminal at repository location")
	}

	// MARK: - Computed Properties

	private var buttonLabel: String {
		abbreviationMode.isAbbreviated ? "Term" : "Terminal"
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
