import ComposableArchitecture
import SwiftUI

// MARK: - Android Studio Button View

struct AndroidStudioButtonView: View {
	let store: StoreOf<AndroidStudioButtonReducer>
	@Shared(.isAbbreviated)
	private var isAbbreviated = false

	var body: some View {
		ToolButton(
			label: store.isOpening
				? (isAbbreviated ? "Open" : "Opening")
				: (isAbbreviated ? "AS" : "Android Studio"),
			icon: .customImage("android"),
			tooltip: buttonTooltip,
			isProcessing: store.isOpening,
			tint: store.isOpening ? .green : nil,
			action: { store.send(.openAndroidStudioButtonTapped) }
		)
		.alert(store: store.scope(state: \.$alert, action: \.alert))
	}

	// MARK: - Computed Properties

	private var buttonTooltip: String {
		if store.isOpening {
			"Opening Android Studio..."
		}
		else {
			"Open in Android Studio"
		}
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
