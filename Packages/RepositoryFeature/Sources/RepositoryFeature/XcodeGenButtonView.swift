import AppUI
import ComposableArchitecture
import SwiftUI
import ToolsIntegration

// MARK: - XcodeGen Button View

struct XcodeGenButtonView: View {
	@Bindable
	var store: StoreOf<XcodeGenButtonReducer>

	var body: some View {
		Group {
			if let runningAction = store.runningAction {
				GitOperationProgressView(
					text: Self.progressText(for: runningAction),
					color: .teal,
					helpText: Self.progressHelpText(for: runningAction)
				)
			}
			else {
				PopUpMenuButton("XcodeGen") {
					store.menuEntries
				}
			}
		}
		.fixedSize()
		.xcodeGenPresentations(store: store)
	}

	static func progressText(for action: XcodeGenAction) -> String {
		switch action {
		case .generate, .generateUsingCache:
			"Generating..."
		case .dumpSummary:
			"Reading spec..."
		}
	}

	private static func progressHelpText(for action: XcodeGenAction) -> String {
		switch action {
		case .generate:
			"Generating Xcode project with XcodeGen..."
		case .generateUsingCache:
			"Generating Xcode project with XcodeGen, if the spec changed..."
		case .dumpSummary:
			"Summarising the XcodeGen spec..."
		}
	}
}

extension Store where State == XcodeGenButtonReducer.State, Action == XcodeGenButtonReducer.Action {
	/// The XcodeGen menu as an entry of another menu (the repository row's "⋯" menu): a submenu,
	/// or while a command runs a disabled entry naming it.
	///
	/// A menu entry cannot present anything, so whoever shows this must also apply
	/// `xcodeGenPresentations(store:)` to a view outside the menu.
	var submenuEntry: PopUpMenuEntry {
		if let runningAction = self.runningAction {
			.action(PopUpMenuAction(
				"XcodeGen: \(XcodeGenButtonView.progressText(for: runningAction))",
				systemImage: "gearshape.2",
				isEnabled: false
			) {})
		}
		else {
			.submenu("XcodeGen", systemImage: "gearshape.2") {
				self.menuEntries
			}
		}
	}
}

/// The menu's entries, shared by `XcodeGenButtonView` and `submenuEntry`.
private extension Store where State == XcodeGenButtonReducer.State, Action == XcodeGenButtonReducer.Action {
	@PopUpMenuBuilder
	var menuEntries: [PopUpMenuEntry] {
		PopUpMenuAction("Generate", systemImage: "hammer") {
			self.send(.generateTapped)
		}
		PopUpMenuAction("Generate (Use Cache)", systemImage: "hammer.circle") {
			self.send(.generateUsingCacheTapped)
		}
		PopUpMenuEntry.divider
		PopUpMenuAction("Edit Spec", systemImage: "pencil") {
			self.send(.editSpecTapped)
		}
		PopUpMenuAction("Spec Summary", systemImage: "magnifyingglass") {
			self.send(.dumpSummaryTapped)
		}
	}
}

extension View {
	/// The XcodeGen menu's sheet. Applied by `XcodeGenButtonView` itself; a `submenuEntry` needs
	/// it on a view outside the menu it sits in.
	func xcodeGenPresentations(store: StoreOf<XcodeGenButtonReducer>) -> some View {
		modifier(XcodeGenPresentations(store: store))
	}
}

private struct XcodeGenPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<XcodeGenButtonReducer>

	@Environment(\.presentsButtonAlerts)
	private var presentsAlerts

	func body(content: Content) -> some View {
		content
			.sheet(item: presentsAlerts ? $store.scope(\.$alert, action: \.alert) : .constant(nil)) { alertStore in
				ScrollableAlertView(store: alertStore)
			}
	}
}

#Preview {
	XcodeGenButtonView(
		store: Store(
			initialState: XcodeGenButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				iosSubfolderPath: ""
			),
			reducer: {
				XcodeGenButtonReducer()
			}
		)
	)
}
