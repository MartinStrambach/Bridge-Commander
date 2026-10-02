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

	@Environment(\.presentsButtonAlerts)
	private var presentsAlerts

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
				// `ActionButton` has no processing state, so a tuist install & generate started
				// from the terminal toolbar ran with nothing on screen. Swap in a progress pill
				// instead, the same way the Tuist menu beside it does.
				if store.projectState.isProcessing {
					GitOperationProgressView(
						text: "\(buttonLabel)…",
						color: .orange,
						helpText: buttonTooltip
					)
					.fixedSize()
				}
				else {
					ActionButton(
						icon: .systemImage(buttonIcon),
						tooltip: buttonTooltip,
						color: store.projectPath == nil ? .orange : nil,
						action: { store.send(.openProject) }
					)
				}
			}
		}
		.disabled(isNotFound)
		.alert(presentsAlerts ? $store.scope(\.$alert, action: \.alert) : .constant(nil))
		.sheet(item: presentsAlerts ? $store.scope(\.$errorAlert, action: \.errorAlert) : .constant(nil)) { alertStore in
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
