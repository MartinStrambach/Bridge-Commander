import ComposableArchitecture
import SwiftUI
import AppUI

// MARK: - Android Studio Button View

struct AndroidStudioButtonView: View {
	enum Style {
		case tool
		case compact
	}

	@Bindable
	var store: StoreOf<AndroidStudioButtonReducer>

	var style: Style = .tool

	private var buttonTooltip: String {
		if store.isOpening {
			"Opening Android Studio..."
		}
		else {
			"Open in Android Studio"
		}
	}

	var body: some View {
		switch style {
		case .tool:
			ToolButton(
				label: store.isOpening ? "Opening" : "Android Studio",
				icon: .customImage("android"),
				tooltip: buttonTooltip,
				isProcessing: store.isOpening,
				tint: store.isOpening ? .green : nil,
				action: { store.send(.openAndroidStudioButtonTapped) }
			)
			.alert($store.scope(state: \.$alert, action: \.alert))

		case .compact:
			ActionButton(
				icon: .customImage("android"),
				tooltip: buttonTooltip,
				action: { store.send(.openAndroidStudioButtonTapped) }
			)
			.alert($store.scope(state: \.$alert, action: \.alert))
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
