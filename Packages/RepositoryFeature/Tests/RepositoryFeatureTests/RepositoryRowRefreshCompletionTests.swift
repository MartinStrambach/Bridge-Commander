import ComposableArchitecture
import GitCore
import GitHosting
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Repository row refresh completion")
struct RepositoryRowRefreshCompletionTests {
	/// A row on the default branch: the follow-up YouTrack and PR fetches
	/// resolve to nil without touching any live dependency.
	private func makeRow() -> RepositoryRowReducer.State {
		var state = RepositoryRowReducer.State(
			path: "/repos/app",
			name: "app",
			branchName: "master",
			ticketIdRegex: "[A-Z]+-\\d+"
		)
		state.isRefreshing = true
		state.prState = .ready
		state.ticketState = .waitingToCodeReview
		return state
	}

	@Test("stays refreshing until both YouTrack and PR fetches settle")
	@MainActor
	func clearsFlagAfterAllFetchesSettle() async {
		let store = TestStore(initialState: makeRow()) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "# branch.head master"), false))
		#expect(store.state.isRefreshing)

		await store.receive(\.refreshDidFinish)
		#expect(!store.state.isRefreshing)

		// Both fetch results were processed before the refresh finished.
		#expect(store.state.ticketState == nil)
		#expect(store.state.prState == nil)
		await store.finish()
	}

	@Test("stops refreshing when the status fetch fails")
	@MainActor
	func clearsFlagWhenStatusFails() async {
		let store = TestStore(initialState: makeRow()) {
			RepositoryRowReducer()
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "", didSucceed: false), false))
		await store.receive(\.refreshDidFinish)
		#expect(!store.state.isRefreshing)

		// No follow-up fetches ran, so their state is untouched.
		#expect(store.state.ticketState == .waitingToCodeReview)
		#expect(store.state.prState == .ready)
		await store.finish()
	}

	/// A store whose refresh fan-out resolves without touching git or Xcode.
	@MainActor
	private func makeIdleStore() -> TestStoreOf<RepositoryRowReducer> {
		var state = makeRow()
		state.isRefreshing = false
		let store = TestStore(initialState: state) {
			RepositoryRowReducer()
		} withDependencies: {
			var gitClient = GitClient()
			gitClient.getCurrentBranch = { _ in GitPorcelainStatus(parsing: "", didSucceed: false) }
			$0[GitClient.self] = gitClient

			var xcodeClient = XcodeClient()
			xcodeClient.hasXcodeProject = { _, _ in false }
			xcodeClient.findXcodeProject = { _, _, _ in nil }
			$0[XcodeClient.self] = xcodeClient
		}
		store.exhaustivity = .off
		return store
	}

	@Test("a plain refresh does not mark the row as refreshing")
	@MainActor
	func plainRefreshLeavesFlagUnset() async {
		let store = makeIdleStore()

		await store.send(.refresh)
		#expect(!store.state.isRefreshing)
		await store.finish()
	}

	@Test("a progress-tracked refresh marks the row as refreshing")
	@MainActor
	func trackedRefreshSetsFlag() async {
		let store = makeIdleStore()

		await store.send(.refreshWithProgress)
		#expect(store.state.isRefreshing)
	}
}
