import ComposableArchitecture
import Foundation
import GitCore
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal toolbar's buttons are copies of the opened row's state. Closing the last tab of
// the opened repository switches the panel to another repository's session, and used to do so
// without re-copying them — so the Xcode button, git menu etc. kept acting on the closed one.
@Suite("Terminal toolbar re-sync when the panel falls back to another repository")
@MainActor
struct TerminalToolbarResyncTests {
	@Test("killing the repository's last tab re-syncs the toolbar to the repository shown next")
	func killLastTabResyncsToolbar() async {
		let store = await makeStoreShowingAlpha()

		let alphaSession = store.state.terminalLayout?.activeSessionId
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/alpha")

		await store.send(.terminalLayout(.killTab(sessionId: alphaSession!)))

		expectToolbarShows("/repos/beta", in: store.state)
	}

	@Test("killing the opened repository re-syncs the toolbar to the repository shown next")
	func killRepoResyncsToolbar() async {
		let store = await makeStoreShowingAlpha()

		await store.send(.terminalLayout(.killRepo(repositoryPath: "/repos/alpha")))

		expectToolbarShows("/repos/beta", in: store.state)
	}

	// MARK: - Helpers

	private func expectToolbarShows(_ path: String, in state: RepositoryListReducer.State) {
		let row = state.repositoryGroups[id: path]?.header
		#expect(state.terminalLayout?.activeRepositoryPath == path)
		#expect(row != nil)
		#expect(state.terminalLayout?.gitActionsMenu == row?.gitActionsMenu)
		#expect(state.terminalLayout?.webButton == row?.webButton)
		#expect(state.terminalLayout?.ticketButton == row?.ticketButton)
	}

	/// Two scanned repositories with a terminal each; alpha is the one on screen.
	private func makeStoreShowingAlpha() async -> TestStoreOf<RepositoryListReducer> {
		let store = makeStore()
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			mainRepo("/repos/alpha", name: "alpha"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			mainRepo("/repos/beta", name: "beta"),
		]))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		return store
	}

	private func makeStore() -> TestStoreOf<RepositoryListReducer> {
		var initialState = RepositoryListReducer.State()
		initialState.terminalLayout = TerminalLayoutReducer.State()
		return TestStore(initialState: initialState) {
			RepositoryListReducer()
		} withDependencies: {
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
	}

	private func mainRepo(_ path: String, name: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: name,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}
}
