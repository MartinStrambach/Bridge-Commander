import ComposableArchitecture
import SwiftUI

@main
struct BridgeCommanderApp: App {
	private let repositoryListStore: StoreOf<RepositoryListReducer> = .init(
		initialState: .init(),
		reducer: { RepositoryListReducer() }
	)

	private let settingsStore: StoreOf<SettingsReducer> = .init(
		initialState: .init(),
		reducer: { SettingsReducer() }
	)

	var body: some Scene {
		WindowGroup {
			RepositoryListView(store: repositoryListStore)
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)

		Settings {
			SettingsView(store: settingsStore)
		}
	}
}
