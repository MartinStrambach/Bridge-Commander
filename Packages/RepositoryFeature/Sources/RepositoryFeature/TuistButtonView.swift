import ComposableArchitecture
import SwiftUI
import AppUI
import ToolsIntegration

// MARK: - Tuist Button View

struct TuistButtonView: View {
	@Bindable
	var store: StoreOf<TuistButtonReducer>

	/// Read here and applied to the menu's label as a plain font: a `.borderlessButton` menu's
	/// label is flattened by AppKit, which drops `scaledFont`'s environment lookup and keeps only
	/// a font set directly on the `Text`.
	@Environment(\.uiFontScale)
	private var uiFontScale

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
				Menu {
					TuistMenuItems(store: store)
				} label: {
					Text("Tuist")
						.font(.system(size: 12 * uiFontScale))
				}
				.menuStyle(.borderlessButton)
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

/// The Tuist menu as a submenu of another menu (the repository row's "⋯" menu). While a command
/// runs it is a disabled entry naming it instead.
///
/// A menu entry cannot present anything, so whoever shows this must also apply
/// `tuistPresentations(store:)` to a view outside the menu.
struct TuistSubmenu: View {
	let store: StoreOf<TuistButtonReducer>

	var body: some View {
		if let runningAction = store.runningAction {
			Button {} label: {
				Label("Tuist: \(TuistButtonView.progressText(for: runningAction))", systemImage: "hammer")
			}
			.disabled(true)
		}
		else {
			Menu {
				TuistMenuItems(store: store)
			} label: {
				Label("Tuist", systemImage: "hammer")
			}
		}
	}
}

/// The menu's entries, shared by `TuistButtonView` and `TuistSubmenu`.
private struct TuistMenuItems: View {
	let store: StoreOf<TuistButtonReducer>

	var body: some View {
		Group {
			Button {
				store.send(.generateTapped)
			} label: {
				Label("Generate", systemImage: "hammer")
			}

			Button {
				store.send(.generateWithoutCacheTapped)
			} label: {
				Label("Generate (No Cache)", systemImage: "hammer.circle")
			}

			Button {
				store.send(.installTapped)
			} label: {
				Label("Install", systemImage: "arrow.down.circle")
			}

			Button {
				store.send(.installUpdateTapped)
			} label: {
				Label("Install (Update)", systemImage: "arrow.down.circle.dotted")
			}

			Button {
				store.send(.cacheTapped)
			} label: {
				Label("Cache", systemImage: "tray")
			}

			Button {
				store.send(.installCacheAndGenerateTapped)
			} label: {
				Label("Install, Cache & Generate", systemImage: "wand.and.stars")
			}

			Button {
				store.send(.editTapped)
			} label: {
				Label("Edit", systemImage: "pencil")
			}

			Button {
				store.send(.inspectDependenciesTapped)
			} label: {
				Label("Inspect", systemImage: "magnifyingglass")
			}

			Menu {
				Group {
					Button {
						store.send(.cleanTapped(nil))
					} label: {
						Label("Everything", systemImage: "paintbrush")
					}

					Divider()

					ForEach(TuistCleanCategory.allCases, id: \.self) { category in
						Button {
							store.send(.cleanTapped(category))
						} label: {
							Label(category.displayName, systemImage: category.systemImage)
						}
					}
				}
				// A submenu's content does not inherit the style applied around it.
				.labelStyle(.titleAndIcon)
			} label: {
				Label("Clean", systemImage: "paintbrush")
			}
		}
		// macOS 27 no longer draws a menu item's icon for a bare `Label`; ask for it explicitly.
		.labelStyle(.titleAndIcon)
	}
}

extension View {
	/// The Tuist menu's error sheet. Applied by `TuistButtonView` itself; a `TuistSubmenu` needs
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
