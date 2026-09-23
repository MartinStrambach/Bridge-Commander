import AppIntents
import ComposableArchitecture
import RepositoryFeature
import Settings
import SwiftUI

@main
struct BridgeCommanderApp: App {
	private let settingsStore: StoreOf<SettingsReducer> = .init(
		initialState: .init(),
		reducer: { SettingsReducer() }
	)

	/// Watched only so Siri learns the repository names: the phrases that name a repository
	/// are built from `RepositoryEntityQuery.suggestedEntities()`, and the system re-reads
	/// those only when asked to; the Spotlight index is rebuilt at the same moments.
	@SharedReader(.trackedRepoPaths) private var trackedRepoPaths: [String] = []

	var body: some Scene {
		WindowGroup {
			RootRepositoryView()
				.task(id: trackedRepoPaths) {
					BridgeCommanderShortcuts.updateAppShortcutParameters()
					await RepositoryIndexer.reindexLoggingFailure(paths: trackedRepoPaths)
				}
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)

		Settings {
			SettingsView(store: settingsStore)
		}
	}
}
