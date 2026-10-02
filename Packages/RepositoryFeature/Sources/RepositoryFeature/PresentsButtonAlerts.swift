import SwiftUI

extension EnvironmentValues {
	/// Whether the Xcode and Tuist buttons under this view present their alerts and sheets.
	///
	/// The terminal toolbar shows the opened row's own button stores, and the repository list
	/// stays mounted (at opacity 0) underneath it — so while the terminal is open the same
	/// alert state is bound by two views. `RepositoryListView` turns this off for the hidden
	/// list, leaving the visible view as the only one that presents.
	@Entry
	var presentsButtonAlerts = true
}
