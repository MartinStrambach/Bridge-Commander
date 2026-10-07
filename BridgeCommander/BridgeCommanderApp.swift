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

	/// Created with the app, as Sparkle expects: a started updater schedules its background
	/// checks from here.
	private let updaterController = SPUStandardUpdaterController(
		startingUpdater: startsUpdater,
		updaterDelegate: nil,
		userDriverDelegate: nil
	)

	var body: some Scene {
		WindowGroup(id: "main") {
			RootRepositoryView()
				.appUIFontSize()
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		// Opens filling the visible area of the screen it lands on, every launch.
		.defaultWindowPlacement { _, context in
			let screen = context.defaultDisplay.visibleRect
			return WindowPlacement(.center, size: screen.size)
		}
		.restorationBehavior(.disabled)
		.commands {
			CommandGroup(after: .appInfo) {
				CheckForUpdatesView(updater: updaterController.updater)
			}
		}

		Settings {
			SettingsView(store: settingsStore) {
				UpdateSettingsView(updater: updaterController.updater)
			}
			.appUIFontSize()
		}
	}
}
