import ComposableArchitecture
import SwiftUI
import AppUI
import ToolsIntegration

// MARK: - Tuist Button View

struct TuistButtonView: View {
	@Bindable
	var store: StoreOf<TuistButtonReducer>

	var body: some View {
		Group {
			if let runningAction = store.runningAction {
				GitOperationProgressView(
					text: Self.progressText(for: runningAction),
					color: .purple,
					helpText: progressHelpText(for: runningAction)
				)
			}
			else {
				PopUpMenuButton("Tuist") {
					store.menuEntries
				}
			}
		}
		.fixedSize()
		.tuistPresentations(store: store)
	}

	// MARK: - Helper Methods

	static func progressText(for action: TuistAction) -> String {
		switch action {
		case .generate, .generateWithoutCache:
			"Generating..."
		case .install, .installUpdate:
			"Installing..."
		case .cache:
			"Caching..."
		case .installCacheAndGenerate:
			"Installing, Caching & Generating..."
		case .edit:
			"Opening..."
		case .inspectDependencies:
			"Inspecting..."
		case .clean:
			"Cleaning..."
		}
	}

	private func progressHelpText(for action: TuistAction) -> String {
		switch action {
		case .generate:
			"Generating Xcode project with Tuist..."
		case .generateWithoutCache:
			"Generating Xcode project without binary cache..."
		case .install:
			"Installing Tuist dependencies..."
		case .installUpdate:
			"Installing and updating Tuist dependencies..."
		case .cache:
			"Caching Tuist targets..."
		case .installCacheAndGenerate:
			"Running install, cache and generate..."
		case .edit:
			"Opening Tuist project for editing..."
		case .inspectDependencies:
			"Inspecting implicit dependencies..."
		case let .clean(category):
			if let category {
				"Cleaning the Tuist \(category.displayName) cache..."
			}
			else {
				"Cleaning all Tuist caches..."
			}
		}
	}
}

extension Store where State == TuistButtonReducer.State, Action == TuistButtonReducer.Action {
	/// The Tuist menu as an entry of another menu (the repository row's "⋯" menu): a submenu, or
	/// while a command runs a disabled entry naming it.
	///
	/// A menu entry cannot present anything, so whoever shows this must also apply
	/// `tuistPresentations(store:)` to a view outside the menu.
	var submenuEntry: PopUpMenuEntry {
		if let runningAction = self.runningAction {
			.action(PopUpMenuAction(
				"Tuist: \(TuistButtonView.progressText(for: runningAction))",
				systemImage: "hammer",
				isEnabled: false
			) {})
		}
		else {
			.submenu("Tuist", systemImage: "hammer") {
				self.menuEntries
			}
		}
	}
}

/// The menu's entries, shared by `TuistButtonView` and `submenuEntry`.
private extension Store where State == TuistButtonReducer.State, Action == TuistButtonReducer.Action {
	@PopUpMenuBuilder
	var menuEntries: [PopUpMenuEntry] {
		PopUpMenuAction("Generate", systemImage: "hammer") {
			self.send(.generateTapped)
		}
		PopUpMenuAction("Generate (No Cache)", systemImage: "hammer.circle") {
			self.send(.generateWithoutCacheTapped)
		}
		PopUpMenuAction("Install", systemImage: "arrow.down.circle") {
			self.send(.installTapped)
		}
		PopUpMenuAction("Install (Update)", systemImage: "arrow.down.circle.dotted") {
			self.send(.installUpdateTapped)
		}
		PopUpMenuAction("Cache", systemImage: "tray") {
			self.send(.cacheTapped)
		}
		PopUpMenuAction("Install, Cache & Generate", systemImage: "wand.and.stars") {
			self.send(.installCacheAndGenerateTapped)
		}
		PopUpMenuAction("Edit", systemImage: "pencil") {
			self.send(.editTapped)
		}
		PopUpMenuAction("Inspect", systemImage: "magnifyingglass") {
			self.send(.inspectDependenciesTapped)
		}
		PopUpMenuEntry.submenu("Clean", systemImage: "paintbrush") {
			PopUpMenuAction("Everything", systemImage: "paintbrush") {
				self.send(.cleanTapped(nil))
			}
			PopUpMenuEntry.divider
			for category in TuistCleanCategory.allCases {
				PopUpMenuAction(category.displayName, systemImage: category.systemImage) {
					self.send(.cleanTapped(category))
				}
			}
		}
	}
}

extension View {
	/// The Tuist menu's error sheet. Applied by `TuistButtonView` itself; a `submenuEntry` needs
	/// it on a view outside the menu it sits in.
	func tuistPresentations(store: StoreOf<TuistButtonReducer>) -> some View {
		modifier(TuistPresentations(store: store))
	}
}

private struct TuistPresentations: ViewModifier {
	@Bindable
	var store: StoreOf<TuistButtonReducer>

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
	TuistButtonView(
		store: Store(
			initialState: TuistButtonReducer.State(
				repositoryPath: "/Users/test/projects/my-project",
				iosSubfolderPath: ""
			),
			reducer: {
				TuistButtonReducer()
			}
		)
	)
}
