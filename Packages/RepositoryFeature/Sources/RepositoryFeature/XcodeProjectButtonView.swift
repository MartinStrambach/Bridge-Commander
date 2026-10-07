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

/// The Xcode button as an entry of another menu (the repository row's "⋯" menu).
///
/// A menu entry cannot present anything, so whoever shows this must also apply
/// `xcodeProjectPresentations(store:)` to a view outside the menu.
struct XcodeProjectMenuItem: View {
	let store: StoreOf<XcodeProjectButtonReducer>

	private var title: String {
		switch store.projectState {
		case .idle, .error:
			if store.projectPath != nil {
				"Open in Xcode"
			}
			else if store.usesTuist {
				"Install & Generate Xcode Project"
			}
			else {
				"Xcode Project Not Found"
			}

		default:
			store.projectState.displayMessage
		}
	}

	var body: some View {
		Button {
			store.send(.openProject)
		} label: {
			Label(title, systemImage: store.projectPath == nil ? "exclamationmark.triangle" : "hammer.fill")
		}
		.disabled(
			store.projectState.isProcessing
				|| (store.projectState == .idle && store.projectPath == nil && !store.usesTuist)
		)
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
