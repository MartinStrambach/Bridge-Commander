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
		WindowGroup {
			RootRepositoryView()
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)
		.commands {
			CommandGroup(after: .appInfo) {
				CheckForUpdatesView(updater: updaterController.updater)
			}
		}

		Settings {
			SettingsView(store: settingsStore)
		}
	}
}
