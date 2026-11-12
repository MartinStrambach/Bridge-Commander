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
		.xcodeProjectPresentations(store: store)
	}
}

extension Store where State == XcodeProjectButtonReducer.State, Action == XcodeProjectButtonReducer.Action {
	/// The button as an entry of the repository row's "⋯" menu.
	var menuEntry: PopUpMenuAction {
		PopUpMenuAction(
			menuEntryTitle,
			systemImage: self.projectPath == nil ? "exclamationmark.triangle" : "hammer.fill",
			isEnabled: !(
				self.projectState.isProcessing
					|| (self.projectState == .idle && self.projectPath == nil && !self.usesTuist)
			)
		) {
			self.send(.openProject)
		}
	}

	private var menuEntryTitle: String {
		switch self.projectState {
		case .idle, .error:
			if self.projectPath != nil {
				"Open in Xcode"
			}
			else if self.usesTuist {
				"Install & Generate Xcode Project"
			}
			else {
				"Xcode Project Not Found"
			}

		default:
			self.projectState.displayMessage
		}
	}
}

extension View {
	/// The Xcode button's alerts. Applied by `XcodeProjectButtonView` itself; an
	/// `XcodeProjectMenuItem` needs it on a view outside the menu it sits in.
	func xcodeProjectPresentations(store: StoreOf<XcodeProjectButtonReducer>) -> some View {
		modifier(XcodeProjectPresentations(store: store))
	}
}

private struct XcodeProjectPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<XcodeProjectButtonReducer>

	@Environment(\.presentsButtonAlerts)
	private var presentsAlerts

	func body(content: Content) -> some View {
		content
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
