import ComposableArchitecture
import SwiftUI
import AppUI
import ToolsIntegration

// MARK: - Xcode Project Button View

struct XcodeProjectButtonView: View {
	enum Style {
		case tool
		case compact
	}

	@Bindable
	var store: StoreOf<XcodeProjectButtonReducer>

	var style: Style = .tool

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
			"Installing"

		case .runningTg:
			"Generating"

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
		switch style {
		case .tool:
			ToolButton(
				label: buttonLabel,
				icon: .systemImage(buttonIcon),
				tooltip: buttonTooltip,
				isProcessing: store.projectState.isProcessing,
				tint: store.projectPath == nil ? .orange : nil,
				action: { store.send(.openProject) }
			)
			.alert($store.scope(state: \.$alert, action: \.alert))

		case .compact:
			ActionButton(
				icon: .systemImage(buttonIcon),
				tooltip: buttonTooltip,
				color: store.projectPath == nil ? .orange : nil,
				action: { store.send(.openProject) }
			)
			.alert($store.scope(state: \.$alert, action: \.alert))
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
