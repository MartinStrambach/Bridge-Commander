import Combine
import ComposableArchitecture
import SwiftUI

@main
struct BridgeCommanderApp: App {
	@StateObject
	private var appSettings = AppSettings()

	private let store: StoreOf<RepositoryListReducer> = .init(
		initialState: .init(),
		reducer: { RepositoryListReducer() }
	)

	var body: some Scene {
		WindowGroup {
			RepositoryListView(store: store)
				.environmentObject(appSettings)
		}
		.windowStyle(.hiddenTitleBar)
		.windowResizability(.contentSize)

		Settings {
			SettingsView(settings: appSettings)
		}
	}

	init() {
		let _appSettings = AppSettings()
		_appSettings.objectWillChange.send()
		self._appSettings = StateObject(wrappedValue: _appSettings)
	}

}
