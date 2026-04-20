import AppUI
import ComposableArchitecture
import SwiftUI

struct WebButtonView: View {
	enum Style { case tool, compact }

	let store: StoreOf<WebButtonReducer>
	var style: Style = .tool

	var body: some View {
		ActionButton(
			icon: .systemImage("globe"),
			tooltip: "Open web preview in browser",
			action: { store.send(.openWebButtonTapped) }
		)
	}
}

#Preview {
	WebButtonView(
		store: Store(
			initialState: WebButtonReducer.State(
				repositoryPath: "/Users/test/repo",
				webIndexPath: "dist/index.html"
			),
			reducer: { WebButtonReducer() }
		)
	)
}
