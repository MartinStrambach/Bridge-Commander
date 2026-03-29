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

	var body: some Scene {
		WindowGroup {
			RootRepositoryView()
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)

		Settings {
			SettingsView(store: settingsStore)
		}
	}
}
