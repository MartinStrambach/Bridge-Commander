import ComposableArchitecture
import RepositoryFeature
import Settings
import Sparkle
import SwiftUI

@main
struct BridgeCommanderApp: App {
	private let settingsStore: StoreOf<SettingsReducer> = .init(
		initialState: .init(),
		reducer: { SettingsReducer() }
	)

	/// The repositories and terminals, shared by the main window and the menu bar extra, and
	/// outliving the window: closing it leaves the shells running and the menu bar current.
	private let model = RepositoryAppModel()

	@Shared(.showsMenuBarExtra)
	private var showsMenuBarExtra = true

	/// Created with the app, as Sparkle expects: a started updater schedules its background
	/// checks from here.
	private let updaterController = SPUStandardUpdaterController(
		startingUpdater: startsUpdater,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)

	var body: some Scene {
		// A single `Window`, not a `WindowGroup`: every window would share the one store and the
		// one set of terminal panes, and a pane can only be in one window.
		Window("Bridge Commander", id: RepositoryAppModel.mainWindowId) {
			RootRepositoryView(model: model)
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		.commands {
			CommandGroup(after: .appInfo) {
				CheckForUpdatesView(updater: updaterController.updater)
			}
		}

		MenuBarExtra(isInserted: menuBarExtraInserted) {
			MenuBarStatusView(model: model)
		} label: {
			MenuBarStatusLabel(model: model)
		}
		.menuBarExtraStyle(.window)

		Settings {
			SettingsView(store: settingsStore) {
				UpdateSettingsView(updater: updaterController.updater)
			}
		}
	}

	/// Writes only a real change. `MenuBarExtra` sets `isInserted` back on every scene update, even
	/// to the value it already has, and a `@Shared` write always counts as a mutation: it
	/// invalidated this body, the rebuilt scene set the binding again, and the app recursed in
	/// SwiftUI's scene update until the stack overflowed at launch (2026-10-06).
	private var menuBarExtraInserted: Binding<Bool> {
		Binding(
			get: { showsMenuBarExtra },
			set: { isInserted in
				guard isInserted != showsMenuBarExtra else { return }
				$showsMenuBarExtra.withLock { $0 = isInserted }
			}
		)
	}
}
