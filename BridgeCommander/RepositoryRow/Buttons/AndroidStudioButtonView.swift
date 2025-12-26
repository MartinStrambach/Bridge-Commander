import ComposableArchitecture
import SwiftUI

// MARK: - Android Studio Button View

struct AndroidStudioButtonView: View {
	let store: StoreOf<AndroidStudioButtonReducer>

	private var buttonTooltip: String {
		if store.isOpening {
			"Opening Android Studio..."
		}
		else {
			"Open in Android Studio"
		}
	}

	var body: some View {
		ToolButton(
			label: store.isOpening ? "Opening" : "Android Studio",
			icon: .customImage("android"),
			tooltip: buttonTooltip,
			isProcessing: store.isOpening,
			tint: store.isOpening ? .green : nil,
			action: { store.send(.openAndroidStudioButtonTapped) }
		)
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}

}

#Preview {
	AndroidStudioButtonView(
		store: Store(
			initialState: AndroidStudioButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				AndroidStudioButtonReducer()
			}
		)
	)
}
