import ComposableArchitecture
import SwiftUI

// MARK: - Xcode Project Button View

struct XcodeProjectButtonView: View {
	let store: StoreOf<XcodeProjectButtonReducer>

	@Shared(.isAbbreviated)
	private var isAbbreviated = false

	private var buttonLabel: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				isAbbreviated ? "Gen" : "Generate"
			}
			else {
				isAbbreviated ? "Xcd" : "Xcode"
			}

		case .checking:
			isAbbreviated ? "Chck" : "Checking"

		case .runningTi:
			isAbbreviated ? "ti" : "Running ti"

		case .runningTg:
			isAbbreviated ? "tg" : "Running tg"

		case .opening:
			isAbbreviated ? "Opn" : "Opening"

		case .error:
			isAbbreviated ? "Xcd" : "Xcode"
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
