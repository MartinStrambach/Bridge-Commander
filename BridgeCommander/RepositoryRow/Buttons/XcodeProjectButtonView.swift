import ComposableArchitecture
import SwiftUI

// MARK: - Xcode Project Button View

struct XcodeProjectButtonView: View {
	let store: StoreOf<XcodeProjectButtonReducer>

	private var buttonLabel: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				"Generate"
			}
			else {
				"Xcode"
			}

		case .checking:
			"Checking"

		case .runningTi:
			"Running ti"

		case .runningTg:
			"Running tg"

		case .opening:
			"Opening"

		case .error:
			"Xcode"
		}
	}

	private var buttonIcon: String {
		if store.projectPath == nil, store.projectState == .idle {
			"exclamationmark.triangle"
		}
		else {
			"hammer"
		}
	}

	private var buttonTooltip: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				"Xcode project not found - click to generate"
			}
			else {
				"Open Xcode project or workspace"
			}

		default:
			store.projectState.displayMessage
		}
	}

	var body: some View {
		ToolButton(
			label: buttonLabel,
			icon: .systemImage(buttonIcon),
			tooltip: buttonTooltip,
			isProcessing: store.projectState.isProcessing,
			tint: store.projectPath == nil ? .orange : nil,
			action: { store.send(.openProject) }
		)
		.alert(store: store.scope(state: \.$alert, action: \.alert))
		.task {
			store.send(.onAppear)
		}
	}

}

#Preview {
	XcodeProjectButtonView(
		store: Store(
			initialState: XcodeProjectButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project"
			),
			reducer: {
				XcodeProjectButtonReducer()
			}
		)
	)
}
