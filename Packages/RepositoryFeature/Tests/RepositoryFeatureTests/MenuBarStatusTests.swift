import ComposableArchitecture
import Foundation
import GitCore
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The menu bar extra summarises the list while the main window may be closed: what each row has to
// push or pull, and which terminal tabs wait on the user.
@Suite("Menu bar status")
@MainActor
struct MenuBarStatusTests {
	// MARK: - Sync state

	@Test("a row whose status has not been fetched reads as unknown, not as up to date")
	func unfetchedRowIsUnknown() {
		// The initial counts are zeros and `hasRemoteBranch` true — exactly "up to date" — so
		// reading them before a fetch would report every unloaded row as in sync.
		let row = makeRow()

		#expect(MenuBarRepositoryStatus(row: row, waitingSessionCount: 0).sync == .unknown)
	}

	@Test("a fetched row reports its upstream, or the commits each way")
	func fetchedRowSync() {
		var row = makeRow()
		row.hasFetchedStatus = true
		#expect(MenuBarRepositoryStatus(row: row, waitingSessionCount: 0).sync == .upToDate)

		row.unpushedCommitCount = 2
		row.commitsBehindCount = 1
		#expect(MenuBarRepositoryStatus(row: row, waitingSessionCount: 0).sync == .diverged(ahead: 2, behind: 1))

		row.hasRemoteBranch = false
		#expect(MenuBarRepositoryStatus(row: row, waitingSessionCount: 0).sync == .unpublished)
	}

	@Test("a successful status fetch marks the row fetched; a failed one does not")
	func statusFetchMarksRowFetched() async {
		let store = TestStore(initialState: makeRow()) {
			RepositoryRowReducer()
		} withDependencies: {
			$0[GitClient.self].getOriginRemote = { _ in nil }
		}
		store.exhaustivity = .off

		await store.send(.didFetchStatus(GitPorcelainStatus(parsing: "", didSucceed: false), false))
		#expect(!store.state.hasFetchedStatus)

		await store.send(.didFetchStatus(
			GitPorcelainStatus(parsing: "# branch.head feature\n# branch.upstream origin/feature\n# branch.ab +3 -0"),
			false
		))
		await store.finish()
		#expect(store.state.hasFetchedStatus)
		#expect(store.state.unpushedCommitCount == 3)
	}

	// MARK: - Waiting tabs

	@Test("lists the waiting tabs by location, and counts them on their rows")
	func waitingSessions() async {
		let store = await makeListStore()
		var waiting = TerminalSession(repositoryPath: "/repos/alpha-fix", tabIndex: 2)
		waiting.status = .waitingForInput
		var sibling = TerminalSession(repositoryPath: "/repos/alpha-fix", tabIndex: 1)
		sibling.status = .active
		await store.send(.view(.onAppear))
		var state = store.state
		state.terminalSessions = [sibling, waiting]

		#expect(state.menuBarWaitingSessions == [
			MenuBarWaitingSession(id: waiting.id, location: "alpha-fix · Terminal 2"),
		])
		#expect(state.menuBarRepositories.map(\.id) == ["/repos/alpha", "/repos/alpha-fix", "/repos/beta"])
		#expect(state.menuBarRepositories.map(\.waitingSessionCount) == [0, 1, 0])
	}

	@Test("clicking a waiting tab opens the window on it")
	func waitingSessionTapped() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .waitingForInput
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let activated = LockIsolated(false)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].activateApp = { activated.setValue(true) }
		}
		store.exhaustivity = .off

		await store.send(.menuBar(.waitingSessionTapped(sessionId: session.id)))
		await store.receive(\.terminalNotificationTapped)

		#expect(store.state.mainWindowRequestCount == 1)
		#expect(store.state.terminalLayout?.activeSessionId == session.id)
		#expect(activated.value)
	}

	// MARK: - Loading

	@Test("opening the menu loads every row the list has not, collapsed or off screen")
	func appearedLoadsUnloadedRows() async {
		let store = await makeListStore()
		#expect(allRows(store).allSatisfy { !$0.isLoaded })

		await store.send(.menuBar(.appeared))
		await store.skipReceivedActions()

		#expect(allRows(store).allSatisfy { $0.isLoaded })
	}

	@Test("closing the window keeps the periodic refresh running")
	func windowCloseKeepsRefreshing() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		await store.send(.view(.onAppear)) {
			$0.isWindowOpen = true
		}
		// Exhaustive: an effect cancelled or started here would be a failure.
		await store.send(.view(.onDisappear)) {
			$0.isWindowOpen = false
		}
	}

	// MARK: - Helpers

	private func makeRow() -> RepositoryRowReducer.State {
		RepositoryRowReducer.State(path: "/repos/app", name: "app", branchName: "feature")
	}

	private func allRows(_ store: TestStoreOf<RepositoryListReducer>) -> [RepositoryRowReducer.State] {
		store.state.repositoryGroups.flatMap { [$0.header] + $0.worktrees }
	}

	private func makeListStore() async -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			// A failed status short-circuits the row's own follow-up fetches.
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off

		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [
			ScannedRepository(path: "/repos/alpha", name: "alpha", directory: "/repos/alpha", isWorktree: false, branchName: "master"),
			ScannedRepository(path: "/repos/alpha-fix", name: "alpha-fix", directory: "/repos/alpha-fix", isWorktree: true, branchName: "fix"),
		]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [
			ScannedRepository(path: "/repos/beta", name: "beta", directory: "/repos/beta", isWorktree: false, branchName: "master"),
		]))
		return store
	}
}
