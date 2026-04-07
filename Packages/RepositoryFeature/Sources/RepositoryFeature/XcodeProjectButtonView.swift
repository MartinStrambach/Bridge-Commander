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

	private var isNotFound: Bool {
		store.projectState == .idle && store.projectPath == nil && !store.usesTuist
	}

	private var buttonLabel: String {
		switch store.projectState {
		case .idle:
			if store.projectPath == nil {
				store.usesTuist ? "Install & Generate" : "Not Found"
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
				store.usesTuist
					? "Xcode project not found - click to run tuist install & generate"
					: "Project not found - check iOS project path or if project exists on disk"
			}
			else {
				"Open Xcode project or workspace"
			}

		default:
			store.projectState.displayMessage
		}
	}

	var body: some View {
		Group {
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
				
			case .compact:
				ActionButton(
					icon: .systemImage(buttonIcon),
					tooltip: buttonTooltip,
					color: store.projectPath == nil ? .orange : nil,
					action: { store.send(.openProject) }
				)
			}
		}
		.disabled(isNotFound)
		.alert($store.scope(state: \.$alert, action: \.alert))
		.sheet(item: $store.scope(state: \.$errorAlert, action: \.errorAlert)) { alertStore in
			ScrollableAlertView(store: alertStore)
		}
	}
}

#Preview {
	XcodeProjectButtonView(
		store: Store(
			initialState: XcodeProjectButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				iosSubfolderPath: ""
			),
			reducer: {
				XcodeProjectButtonReducer()
			}
		)
	)
}
