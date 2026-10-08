import ActivityLog
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

	init() {
		ActivityLog.installUncaughtExceptionHandler()
		let info = Bundle.main.infoDictionary ?? [:]
		ActivityLog.shared.record(
			.app,
			"Launched \(info["CFBundleShortVersionString"] as? String ?? "?") on \(ProcessInfo.processInfo.operatingSystemVersionString)"
		)
		// Entries are written on a background queue; quitting would drop what is still queued.
		NotificationCenter.default.addObserver(
			forName: NSApplication.willTerminateNotification,
			object: nil,
			queue: nil
		) { _ in
			ActivityLog.shared.flush()
		}
	}

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
