import ComposableArchitecture
import SwiftUI

/// The Agents page of the selected instance. `user` decides what it offers (e.g. Run, by the
/// user's grants); the server checks every call again.
struct HomerAgentsView: View {
	let store: StoreOf<HomerAgentsReducer>
	let user: HomerUser

	var body: some View {
		ContentUnavailableView("Agents", systemImage: "square.stack.3d.up")
	}
}

/// The Schedules page of the selected instance: its agents that run on a cron.
struct HomerSchedulesView: View {
	let store: StoreOf<HomerAgentsReducer>

	var body: some View {
		ContentUnavailableView("Schedules", systemImage: "calendar.badge.clock")
	}
}
