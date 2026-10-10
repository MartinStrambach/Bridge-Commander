import SwiftUI

public extension EnvironmentValues {
	/// Whether the row buttons and menus under this view (Xcode, Tuist, YouTrack, Git Actions,
	/// Android Studio) present their alerts, sheets and dialogs.
	///
	/// The terminal toolbar shows the opened row's own button stores, and the repository list
	/// stays mounted (at opacity 0) underneath it — so while the terminal is open the same
	/// alert state is bound by two views. `RepositoryListView` turns this off for the hidden
	/// list, leaving the visible view as the only one that presents. In AppUI rather than
	/// RepositoryFeature so the menus' and buttons' own packages can read it.
	@Entry
	var presentsButtonAlerts = true
}
