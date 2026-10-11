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
			.alert($store.scope(\.$alert, action: \.alert))

		case .compact:
			ActionButton(
				icon: .customImage("android"),
				tooltip: buttonTooltip,
				action: { store.send(.openAndroidStudioButtonTapped) }
			)
			.alert($store.scope(\.$alert, action: \.alert))
		}
	}

	public init(store: StoreOf<AndroidStudioButtonReducer>, style: Style = .tool) {
		self.store = store
		self.style = style
	}

}

public extension Store where State == AndroidStudioButtonReducer.State, Action == AndroidStudioButtonReducer.Action {
	/// The button as an entry of the repository row's "⋯" menu.
	var menuEntry: PopUpMenuAction {
		PopUpMenuAction(
			self.isOpening ? "Opening Android Studio..." : "Open in Android Studio",
			systemImage: "apps.iphone",
			isEnabled: !self.isOpening
		) {
			self.send(.openAndroidStudioButtonTapped)
		}
	}
}

public extension View {
	/// The Android Studio button's error alert, for an `AndroidStudioMenuItem`.
	func androidStudioPresentations(store: StoreOf<AndroidStudioButtonReducer>) -> some View {
		modifier(AndroidStudioPresentations(store: store))
	}
}

private struct AndroidStudioPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<AndroidStudioButtonReducer>

	func body(content: Content) -> some View {
		content.alert($store.scope(\.$alert, action: \.alert))
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
