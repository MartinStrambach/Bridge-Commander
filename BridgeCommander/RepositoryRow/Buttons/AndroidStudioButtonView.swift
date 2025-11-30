import ComposableArchitecture
import SwiftUI

// MARK: - Android Studio Button View

struct AndroidStudioButtonView: View {
	let store: StoreOf<AndroidStudioButtonReducer>
	@EnvironmentObject
	var abbreviationMode: AbbreviationMode

	var body: some View {
		ToolButton(
			label: store.isOpening
				? (abbreviationMode.isAbbreviated ? "Open" : "Opening")
				: (abbreviationMode.isAbbreviated ? "AS" : "Android Studio"),
			icon: .customImage("android"),
			tooltip: buttonTooltip,
			isProcessing: store.isOpening,
			tint: store.isOpening ? .green : nil,
			action: { store.send(.openAndroidStudioButtonTapped) }
		)
		.environmentObject(abbreviationMode)
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
	.environmentObject(AbbreviationMode())
}
