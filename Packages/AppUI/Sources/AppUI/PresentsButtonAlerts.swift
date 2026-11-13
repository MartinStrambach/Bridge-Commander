import SwiftUI

public extension EnvironmentValues {
	/// Whether the row's buttons that the terminal toolbar also shows (Xcode, Tuist, YouTrack,
	/// Android Studio and the git menu) present their alerts, sheets and dialogs under this view.
	///
	/// The terminal toolbar shows the opened row's own button stores, and the repository list
	/// stays mounted (at opacity 0) underneath it — so while the terminal is open the same
	/// alert state is bound by two views. `RepositoryListView` turns this off for the hidden
	/// list, leaving the visible view as the only one that presents. In AppUI rather than
	/// RepositoryFeature so the YouTrack menu's own package can read it.
	@Entry
	var presentsButtonAlerts = true
}
