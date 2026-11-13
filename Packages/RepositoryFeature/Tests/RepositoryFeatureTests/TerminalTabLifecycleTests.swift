import ComposableArchitecture
import Foundation
import GitCore
import Settings
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// The terminal panel's tab actions as `RepositoryListReducer` applies them — the paths around the
// ones the close-tab and persistence suites already cover: closing what is *not* on screen,
// closing the last of everything, a deleted worktree's tabs, retrying a tab, hiding the panel and
// showing it again, and the toolbar's Finish Merge completion.
//
// A session that leaves the state has its shell hung up by `TerminalPanesClient.kill`. The tests
// that close something record what it was given; the others leave it unimplemented, so a shell
// hung up by mistake fails them.
@Suite("Terminal tab lifecycle")
@MainActor
struct TerminalTabLifecycleTests {
	/// What `TerminalPanesClient.kill` was called with, one entry per call.
	private let killed = LockIsolated<[Set<UUID>]>([])

	// MARK: - Closing tabs that are not on screen

	@Test("closing a background tab leaves the tab on screen, and its memory, alone")
	func killBackgroundTabKeepsActiveTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeClosingStore(state(sessions: [alphaOne, alphaTwo], active: alphaTwo))

		await store.send(.terminals(.killTab(sessionId: alphaOne.id))) {
			$0.terminals = TerminalTabs(
				sessions: [alphaTwo],
				panes: [TerminalPane(shown: alphaTwo.id, tabs: [alphaTwo.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id],
				recentSessionIds: [alphaTwo.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[alphaOne.id]])
	}

	@Test("closing a background repository's terminals keeps the panel where it is")
	func killBackgroundRepoKeepsActiveRepo() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		var initial = RepositoryListReducer.State()
		initial.terminals = TerminalTabs(
			sessions: [alpha, betaOne, betaTwo],
			panes: [TerminalPane(shown: alpha.id, tabs: [alpha.id])],
			isPanelVisible: true,
			lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": betaTwo.id],
			recentSessionIds: [alpha.id]
		)
		initial.terminalLayout = TerminalLayoutReducer.State()
		let store = makeClosingStore(initial)

		await store.send(.terminals(.killRepo(repositoryPath: "/repos/beta"))) {
			$0.terminals = TerminalTabs(
				sessions: [alpha],
				panes: [TerminalPane(shown: alpha.id, tabs: [alpha.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": alpha.id],
				recentSessionIds: [alpha.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[betaOne.id, betaTwo.id]])
	}

	// MARK: - Closing the last of everything

	@Test("closing the only tab left anywhere closes the panel")
	func killLastTabClosesPanel() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let store = makeClosingStore(state(sessions: [alpha], active: alpha))

		await store.send(.terminals(.killTab(sessionId: alpha.id))) {
			$0.terminals = TerminalTabs()
			$0.terminalLayout = nil
		}
		await store.finish()
		#expect(killed.value == [[alpha.id]])
	}

	@Test("closing the only repository with terminals closes the panel")
	func killLastRepoClosesPanel() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeClosingStore(state(sessions: [alphaOne, alphaTwo], active: alphaOne))

		await store.send(.terminals(.killRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = TerminalTabs()
			$0.terminalLayout = nil
		}
		await store.finish()
		#expect(killed.value == [[alphaOne.id, alphaTwo.id]])
	}

	// MARK: - A deleted worktree

	@Test("deleting a worktree closes its tabs, and only its tabs")
	func deletedWorktreeClosesItsTabs() async throws {
		let worktreePath = "/repos/alpha-feature"
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
			$0[TerminalPanesClient.self].kill = { [killed] ids in
				killed.withValue { $0.append(Set(ids)) }
			}
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(
			rootPath: "/repos/alpha",
			rows: [mainRepo("/repos/alpha"), worktree(worktreePath)]
		))
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha")))
		await store.receive(\.terminals.sessionBuilt)
		await store.send(.terminals(.selectRepo(repositoryPath: worktreePath)))
		await store.receive(\.terminals.sessionBuilt)
		await store.send(.terminals(.newTabRequested))
		await store.receive(\.terminals.sessionBuilt)
		let main = try #require(store.state.terminals.tabs(of: "/repos/alpha").first)
		let worktreeTabs = store.state.terminals.tabs(of: worktreePath).map(\.id)
		try #require(worktreeTabs.count == 2)

		await store.send(.repositoryGroups(.element(
			id: "/repos/alpha",
			action: .worktrees(.element(id: worktreePath, action: .worktreeDeleted))
		)))

		// The panel goes back to the terminal that is left.
		#expect(store.state.terminals.sessions.map(\.id) == [main.id])
		#expect(store.state.terminals.shownSessionIds == [main.id])
		#expect(store.state.terminals.isPanelVisible)
		await store.finish()
		#expect(killed.value == [Set(worktreeTabs)])
	}

	// MARK: - Hiding the panel

	@Test("hiding the panel keeps every terminal running, and the panes where they were")
	func hidePanelKeepsSessions() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		// `kill` is unimplemented and the store exhaustive: a session dropped here would have
		// its shell hung up, and either fails the test.
		let store = TestStore(initialState: state(sessions: [alpha, beta], active: alpha)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.hidePanelRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [alpha, beta],
				panes: [TerminalPane(shown: alpha.id, tabs: [alpha.id])],
				isPanelVisible: false,
				lastActiveSessionByRepo: ["/repos/alpha": alpha.id],
				recentSessionIds: [alpha.id]
			)
			$0.terminalLayout = nil
		}
		// Hidden already: nothing more to hide.
		await store.send(.terminals(.hidePanelRequested))
	}

	@Test("showing the panel again returns to the tab and pane it was hidden on")
	func showingAgainReturnsWhereItWas() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		// Two panes, neither on its repository's first tab, the keyboard in the second; and
		// alpha's first tab the most recent one that is not on screen, which is where a panel
		// that rebuilt itself from memory would have gone.
		let shown = TerminalTabs(
			sessions: [alphaOne, alphaTwo, betaOne, betaTwo],
			panes: [
				TerminalPane(shown: alphaTwo.id, tabs: [alphaOne.id, alphaTwo.id]),
				TerminalPane(shown: betaTwo.id, tabs: [betaOne.id, betaTwo.id]),
			],
			activePaneIndex: 1,
			isPanelVisible: true,
			lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id, "/repos/beta": betaTwo.id],
			recentSessionIds: [betaOne.id, alphaTwo.id, alphaOne.id, betaTwo.id]
		)
		let hidden = TerminalTabs(
			sessions: shown.sessions,
			panes: shown.panes,
			activePaneIndex: 1,
			isPanelVisible: false,
			lastActiveSessionByRepo: shown.lastActiveSessionByRepo,
			recentSessionIds: shown.recentSessionIds
		)
		var initial = RepositoryListReducer.State()
		initial.terminals = shown
		initial.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.hidePanelRequested)) {
			$0.terminals = hidden
			$0.terminalLayout = nil
		}
		#expect(store.state.terminals.isOnScreen(betaTwo.id) == false)

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = shown
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
		// Shown already: asking again changes nothing.
		await store.send(.view(.showTerminalsRequested))
	}

	@Test("selecting the repository of a hidden panel shows the panel as it was")
	func selectingRepoShowsHiddenPanelAsItWas() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		let shown = TerminalTabs(
			sessions: [alphaOne, alphaTwo, beta],
			panes: [
				TerminalPane(shown: alphaTwo.id, tabs: [alphaOne.id, alphaTwo.id]),
				TerminalPane(shown: beta.id, tabs: [beta.id]),
			],
			activePaneIndex: 0,
			isPanelVisible: true,
			lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id, "/repos/beta": beta.id],
			recentSessionIds: [beta.id, alphaTwo.id]
		)
		var initial = RepositoryListReducer.State()
		initial.terminals = shown
		initial.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: initial) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.hidePanelRequested)) {
			$0.terminals = TerminalTabs(
				sessions: shown.sessions,
				panes: shown.panes,
				isPanelVisible: false,
				lastActiveSessionByRepo: shown.lastActiveSessionByRepo,
				recentSessionIds: shown.recentSessionIds
			)
			$0.terminalLayout = nil
		}

		// The sidebar row of the repository that had the keyboard: its second tab, the split
		// beside it, nothing opened.
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = shown
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	// MARK: - Stale and empty requests

	@Test("selecting a tab that has already closed changes nothing")
	func selectClosedTabIsIgnored() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let store = TestStore(initialState: state(sessions: [alpha], active: alpha)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.selectTab(sessionId: UUID())))
		await store.send(.terminals(.retryTab(sessionId: UUID())))
		await store.send(.terminals(.killTab(sessionId: UUID())))
	}

	@Test("a new tab with no repository on screen opens nothing")
	func newTabWithoutActiveRepoIsIgnored() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.newTabRequested))
	}

	@Test("a new tab is numbered after the highest open one, so a closed number is not reused")
	func newTabNumberFollowsHighestOpenTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 7)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaThree, beta], active: alphaOne)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}
		store.exhaustivity = .off

		await store.send(.terminals(.newTabRequested))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)

		let newTab = store.state.terminals.sessions.last
		#expect(store.state.terminals.sessions.count == 4)
		#expect(newTab?.repositoryPath == "/repos/alpha")
		// 4, not 2 (the gap) and not 8 (another repository's numbering).
		#expect(newTab?.tabIndex == 4)
		#expect(store.state.terminals.activeSessionId == newTab?.id)
	}

	// MARK: - Retrying a tab

	@Test("a retried tab keeps its number and its place in the bar, and is the one on screen")
	func retryKeepsNumberAndPlace() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		var alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		alphaTwo.status = .failed("exec failed")
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeClosingStore(state(sessions: [alphaOne, alphaTwo, alphaThree], active: alphaOne))
		store.exhaustivity = .off

		await store.send(.terminals(.retryTab(sessionId: alphaTwo.id)))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)
		await store.finish()

		let sessions = store.state.terminals.sessions
		#expect(sessions[id: alphaTwo.id] == nil)
		// The bar lays tabs out in array order, so where the replacement lands is where it shows.
		#expect(sessions.map(\.tabIndex) == [1, 2, 3])
		let retried = sessions[1]
		#expect(retried.status == .launching)
		#expect(store.state.terminals.panes.map(\.tabs) == [[alphaOne.id, retried.id, alphaThree.id]])
		#expect(store.state.terminals.activeSessionId == retried.id)
		#expect(store.state.terminals.lastActiveSessionByRepo["/repos/alpha"] == retried.id)
		// The failed session is the one hung up, not the tabs beside it.
		#expect(killed.value == [[alphaTwo.id]])
	}

	// MARK: - Toolbar Finish Merge

	@Test("a finished merge from the toolbar refreshes the opened repository's row")
	func finishMergeRefreshesRow() async {
		let store = await makeStoreShowingAlpha()

		await store.send(.terminalLayout(.finishMergeCompleted(repositoryPath: "/repos/alpha", error: nil)))
		await store.receive { isHeaderRefresh($0, groupId: "/repos/alpha") }
		await store.finish()
		#expect(store.state.alert == nil)
	}

	@Test("a failed merge from the toolbar alerts instead of refreshing")
	func finishMergeFailureAlerts() async {
		let store = await makeStoreShowingAlpha()
		store.exhaustivity = .on

		await store.send(.terminalLayout(.finishMergeCompleted(
			repositoryPath: "/repos/alpha",
			error: .mergeFailed("CONFLICT in App.swift")
		))) {
			$0.alert = AlertState {
				TextState("Finish Merge Failed")
			} message: {
				TextState(GitError.mergeFailed("CONFLICT in App.swift").localizedDescription)
			}
		}
	}

	// MARK: - First tab

	@Test("a repository supporting iOS and Android opens its first terminal in the mobile subfolder")
	func firstTabStartsInMobileSubfolder() async {
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$groupSettings.withLock {
			$0 = [
				"/repos/alpha": RepoGroupSettings(supportsIOS: true, supportsAndroid: true, mobileSubfolderPath: "/mobile/"),
				"/repos/beta": RepoGroupSettings(supportsIOS: true, mobileSubfolderPath: "mobile"),
			]
		}
		let store = await makeStoreShowingAlpha()

		let directories = Dictionary(
			uniqueKeysWithValues: store.state.terminals.sessions.map { ($0.repositoryPath, $0.startingDirectory) }
		)
		#expect(directories["/repos/alpha"] == "/repos/alpha/mobile")
		// The subfolder only applies when both platforms live side by side under it.
		#expect(directories["/repos/beta"] == "/repos/beta")
	}

	// MARK: - Helpers

	/// Sessions only, no rows: enough for tab bookkeeping, which never needs a row. The panel is
	/// open on `active`, its repository's tabs in the one pane.
	private func state(sessions: [TerminalSession], active: TerminalSession) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		var terminals = TerminalTabs(sessions: IdentifiedArray(uniqueElements: sessions))
		terminals.show(active)
		terminals.showPanel()
		state.terminals = terminals
		state.terminalLayout = TerminalLayoutReducer.State()
		return state
	}

	/// An exhaustive store whose closed sessions are recorded in `killed`.
	private func makeClosingStore(_ state: RepositoryListReducer.State) -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalPanesClient.self].kill = { [killed] ids in
				killed.withValue { $0.append(Set(ids)) }
			}
		}
	}

	/// Two scanned repositories with a terminal each; alpha is the one on screen. Non-exhaustive.
	private func makeStoreShowingAlpha() async -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0.continuousClock = ImmediateClock()
			$0[GitClient.self].getCurrentBranch = { _ in
				GitPorcelainStatus(parsing: "", didSucceed: false)
			}
			$0[GitClient.self].getOriginRemote = { _ in nil }
			$0[XcodeClient.self].findXcodeProject = { _, _, _ in nil }
			$0[LastOpenedDirectoryClient.self].load = { nil }
		}
		store.exhaustivity = .off
		await store.send(.didScanGroup(rootPath: "/repos/alpha", rows: [mainRepo("/repos/alpha")]))
		await store.send(.didScanGroup(rootPath: "/repos/beta", rows: [mainRepo("/repos/beta")]))
		// Neither has a tab yet, so each is built on request and placed when it comes back.
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/beta")))
		await store.receive(\.terminals.sessionBuilt)
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha")))
		await store.receive(\.terminals.sessionBuilt)
		return store
	}

	private func mainRepo(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: false,
			branchName: "master"
		)
	}

	private func worktree(_ path: String) -> ScannedRepository {
		ScannedRepository(
			path: path,
			name: (path as NSString).lastPathComponent,
			directory: path,
			isWorktree: true,
			branchName: "feature"
		)
	}

	private func isHeaderRefresh(_ action: RepositoryListReducer.Action, groupId: String) -> Bool {
		guard case let .repositoryGroups(.element(id: id, action: .header(.refresh))) = action else {
			return false
		}
		return id == groupId
	}
}
