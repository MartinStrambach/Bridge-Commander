import ComposableArchitecture
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The System Events probe shells out to osascript and asks System Events to enumerate every
// running process — 110-290ms. It used to run on every manual refresh, because
// refreshButtonTapped cleared both permission flags and refreshRepositories routes through
// .startScan, which sent the checks.
@Suite("Repository list permission checks")
@MainActor
struct RepositoryListPermissionTests {

	@Test("a manual refresh neither re-probes permissions nor hides the warning banner")
	func refreshDoesNotRecheckPermissions() async {
		let store = makeStore()

		store.exhaustivity = .off
		await store.send(.didReceiveSystemEventsPermission(false))
		#expect(store.state.showPermissionDialog)
		store.exhaustivity = .on

		// Exhaustive: a checkPermissions, checkAccessibilityPermission or
		// checkSystemEventsPermission reaching the queue fails here — as does the flag-clearing
		// state mutation refreshButtonTapped used to perform. No repository groups exist, so
		// refreshRepositories short-circuits and nothing else should follow.
		await store.send(.view(.refreshButtonTapped))
		await store.receive(\.refreshRepositories)

		// Clearing the flags also blanked the banner for as long as the probe took to answer.
		#expect(store.state.showPermissionDialog)
		await store.finish()
	}

	// MARK: - Helpers

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
	}
}
