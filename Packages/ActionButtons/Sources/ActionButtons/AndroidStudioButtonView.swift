import AppUI
import ComposableArchitecture
import SwiftUI

// MARK: - Android Studio Button View

public struct AndroidStudioButtonView: View {
	public enum Style {
		case tool
		case compact
	}

	@Bindable
	public var store: StoreOf<AndroidStudioButtonReducer>

	public var style: Style = .tool

	private var buttonTooltip: String {
		if store.isOpening {
			"Opening Android Studio..."
		}
		else {
			"Open in Android Studio"
		}
	}

	public var body: some View {
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

	public init(store: StoreOf<AndroidStudioButtonReducer>, style: Style = .tool) {
		self.store = store
		self.style = style
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
