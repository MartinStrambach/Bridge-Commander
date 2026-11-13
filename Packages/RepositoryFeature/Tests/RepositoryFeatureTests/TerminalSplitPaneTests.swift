import ComposableArchitecture
import Foundation
import SimulatorFeature
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The split as the reducer drives it: which session a split opens, what ⌘W does beside another
// pane, and how the split survives a relaunch. The rules themselves are in `TerminalTabsTests`.
@Suite("Terminal split panes")
@MainActor
struct TerminalSplitPaneTests {
	private static let alpha = "/repos/alpha"
	private static let beta = "/repos/beta"

	/// What `TerminalPanesClient.kill` was called with, one entry per call.
	private let killed = LockIsolated<[Set<UUID>]>([])

	/// The panel showing `panes` left to right, the first with the keyboard. A repository's tabs
	/// that are not on screen belong to the first pane showing it.
	private func makeTerminals(sessions: [TerminalSession], panes: [TerminalSession]) -> TerminalTabs {
		var owned = Set(panes.map(\.id))
		let terminalPanes = panes.map { shown in
			let others = sessions
				.filter { $0.repositoryPath == shown.repositoryPath && !owned.contains($0.id) }
				.map(\.id)
			owned.formUnion(others)
			let tabs = Set(others + [shown.id])
			return TerminalPane(shown: shown.id, tabs: sessions.map(\.id).filter(tabs.contains))
		}
		return TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: terminalPanes,
			isPanelVisible: true,
			lastActiveSessionByRepo: [panes[0].repositoryPath: panes[0].id],
			recentSessionIds: [panes[0].id]
		)
	}

	/// `kill` is unimplemented unless `recordsKills`, so a test that closes no tab fails if a
	/// shell is hung up.
	private func makeStore(
		sessions: [TerminalSession],
		panes: [TerminalSession],
		currentDirectory: String? = nil,
		recordsKills: Bool = false
	) -> TestStoreOf<RepositoryListReducer> {
		var state = RepositoryListReducer.State()
		state.terminals = makeTerminals(sessions: sessions, panes: panes)
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalPanesClient.self].currentDirectory = { _ in currentDirectory }
			if recordsKills {
				$0[TerminalPanesClient.self].kill = { [killed] ids in
					killed.withValue { $0.append(Set(ids)) }
				}
			}
		}
		// A split makes a session with an id of its own, so the tests read the state afterwards
		// instead of spelling it out.
		store.exhaustivity = .off
		return store
	}

	@Test("⌘D opens a new tab of the active repository beside it, where its shell is")
	func splitOpensNewTabBesideActive() async throws {
		let one = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let store = makeStore(sessions: [one], panes: [one], currentDirectory: "/repos/alpha/Sources")

		await store.send(.terminals(.splitRequested))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)

		let added = try #require(store.state.terminals.sessions.last)
		#expect(store.state.terminals.sessions.count == 2)
		#expect(added.repositoryPath == Self.alpha)
		#expect(added.tabIndex == 2)
		#expect(added.startingDirectory == "/repos/alpha/Sources")
		#expect(added.startupCommand == nil)
		#expect(store.state.terminals.shownSessionIds == [one.id, added.id])
		#expect(store.state.terminals.activeSessionId == added.id)
		// The new pane's only tab.
		#expect(store.state.terminals.panes.map(\.tabs) == [[one.id], [added.id]])
	}

	@Test("with three panes ⌘D opens nothing")
	func splitStopsAtThreePanes() async {
		let sessions = (1 ... 3).map { TerminalSession(repositoryPath: Self.alpha, tabIndex: $0) }
		let store = makeStore(sessions: sessions, panes: sessions)
		let before = store.state.terminals

		await store.send(.terminals(.splitRequested))
		await store.finish()

		#expect(store.state.terminals == before)
	}

	@Test("a repository opened in the split shows the tab it was last on")
	func openRepoInSplitShowsItsCurrentTab() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let betaOne = TerminalSession(repositoryPath: Self.beta, tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: Self.beta, tabIndex: 2)
		let store = makeStore(sessions: [alpha, betaOne, betaTwo], panes: [alpha])
		await store.send(.terminals(.selectTab(sessionId: betaTwo.id)))
		await store.send(.terminals(.selectTab(sessionId: alpha.id)))

		await store.send(.terminals(.openRepoInSplit(repositoryPath: Self.beta)))

		#expect(store.state.terminals.sessions.count == 3)
		#expect(store.state.terminals.shownSessionIds == [alpha.id, betaTwo.id])
		#expect(store.state.terminals.activeRepositoryPath == Self.beta)
		// It comes with all of its tabs.
		#expect(store.state.terminals.panes.map(\.tabs) == [[alpha.id], [betaOne.id, betaTwo.id]])
	}

	@Test("a repository with no terminal gets its first one, opened in the split")
	func openRepoInSplitOpensFirstTab() async throws {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let store = makeStore(sessions: [alpha], panes: [alpha])

		await store.send(.terminals(.openRepoInSplit(repositoryPath: Self.beta)))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)

		let added = try #require(store.state.terminals.sessions.last)
		#expect(added.repositoryPath == Self.beta)
		#expect(store.state.terminals.shownSessionIds == [alpha.id, added.id])
		#expect(store.state.terminals.activeSessionId == added.id)
	}

	@Test("selecting a repository in the sidebar changes the active pane only")
	func selectRepoReplacesActivePane() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let gamma = TerminalSession(repositoryPath: "/repos/gamma")
		let store = makeStore(sessions: [alpha, beta, gamma], panes: [alpha, beta])

		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/gamma")))
		#expect(store.state.terminals.shownSessionIds == [gamma.id, beta.id])

		// One already on screen keeps its pane.
		await store.send(.terminals(.selectRepo(repositoryPath: Self.beta)))
		#expect(store.state.terminals.shownSessionIds == [gamma.id, beta.id])
		#expect(store.state.terminals.activeSessionId == beta.id)
	}

	@Test("⌘W beside another pane closes the repository's last tab without asking")
	func closeActiveBesideAnotherPane() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta], recordsKills: true)

		await store.send(.terminals(.closeActiveTabRequested))
		await store.finish()

		#expect(store.state.alert == nil)
		#expect(store.state.terminals.sessions.map(\.id) == [beta.id])
		#expect(store.state.terminals.activeSessionId == beta.id)
		#expect(store.state.terminals.shownSessionIds == [beta.id])
		#expect(store.state.terminalLayout != nil)
		#expect(killed.value == [[alpha.id]])
	}

	@Test("taking a pane out of the split leaves its terminal open as a tab")
	func removingPaneKeepsTerminalRunning() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		// `kill` is unimplemented here: the pane goes, its shell must not.
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])

		await store.send(.terminals(.closePane(sessionId: alpha.id)))
		await store.finish()

		#expect(store.state.terminals.sessions.count == 2)
		#expect(store.state.terminals.shownSessionIds == [beta.id])
		#expect(store.state.terminals.activeRepositoryPath == Self.beta)
	}

	@Test("a run from a simulator pane beside another repository's terminal runs in its own repository")
	func runGoesToTheSimulatorsRepository() async throws {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [beta, alpha])

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "run", title: "App", repositoryPath: Self.alpha)))))

		let run = try #require(store.state.terminals.sessions.last)
		#expect(run.repositoryPath == Self.alpha)
		#expect(run.isRunTab)
		#expect(store.state.terminals.activeSessionId == beta.id)
		// In the bar of the pane showing its repository, which keeps showing what it showed.
		#expect(store.state.terminals.panes.map(\.tabs) == [[beta.id], [alpha.id, run.id]])
		#expect(store.state.terminals.shownSessionIds == [beta.id, alpha.id])
	}

	@Test("hiding the panel keeps the split for when it is shown again")
	func hidingKeepsSplit() async throws {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])
		// The keyboard in the second pane, so coming back to the first would show.
		await store.send(.terminals(.paneFocused(sessionId: beta.id)))
		let split = store.state.terminals

		await store.send(.terminals(.hidePanelRequested))
		#expect(store.state.terminalLayout == nil)
		#expect(store.state.terminals.isPanelVisible == false)
		#expect(store.state.terminals.shownSessionIds == [alpha.id, beta.id])

		await store.send(.view(.showTerminalsRequested))
		#expect(store.state.terminalLayout != nil)
		#expect(store.state.terminals == split)
		#expect(store.state.terminals.activeSessionId == beta.id)

		// A terminal opened from outside the split takes the pane that had the keyboard.
		await store.send(.terminals(.hidePanelRequested))
		await store.send(.view(.openHomeTerminalButtonTapped))
		let home = try #require(store.state.terminals.sessions.last)
		#expect(store.state.terminals.shownSessionIds == [alpha.id, home.id])
		#expect(store.state.terminals.isPanelVisible)
		#expect(store.state.terminalLayout != nil)
	}

	@Test("the split is saved with the tabs and comes back in its order")
	func archiveKeepsSplit() async throws {
		var alpha = TerminalSession(repositoryPath: Self.alpha)
		var beta = TerminalSession(repositoryPath: Self.beta)
		alpha.status = .active
		beta.status = .active
		let terminals = makeTerminals(sessions: [alpha, beta], panes: [beta, alpha])

		let saved = SavedTerminalTabs(terminals, panes: [:])
		#expect(saved.tabs.map(\.paneIndex) == [1, 0])

		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		await store.send(.restoreTerminalTabs)

		let restored = store.state.terminals.sessions
		#expect(store.state.terminals.shownSessionIds == [restored[1].id, restored[0].id])
		#expect(store.state.terminals.activeSessionId == restored[1].id)
		#expect(store.state.terminals.isPanelVisible)
		#expect(store.state.terminalLayout != nil)
	}

	@Test("each pane's tabs are saved with it and come back in the pane they were in")
	func archiveKeepsPaneTabs() async throws {
		var one = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		var two = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		var three = TerminalSession(repositoryPath: Self.alpha, tabIndex: 3)
		one.status = .active
		two.status = .active
		three.status = .active
		// One and two in the left pane, two on screen; three alone in the right one.
		let terminals = TerminalTabs(
			sessions: [one, two, three],
			panes: [
				TerminalPane(shown: two.id, tabs: [one.id, two.id]),
				TerminalPane(shown: three.id, tabs: [three.id]),
			],
			isPanelVisible: true,
			lastActiveSessionByRepo: [Self.alpha: two.id],
			recentSessionIds: [two.id]
		)

		let saved = SavedTerminalTabs(terminals, panes: [:])
		#expect(saved.tabs.map(\.paneIndex) == [0, 0, 1])
		#expect(saved.tabs.map(\.isPaneCurrentTab) == [false, true, true])

		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		await store.send(.restoreTerminalTabs)

		let restored = store.state.terminals.sessions.map(\.id)
		#expect(store.state.terminals.shownSessionIds == [restored[1], restored[2]])
		#expect(store.state.terminals.panes.map(\.tabs) == [[restored[0], restored[1]], [restored[2]]])
		#expect(store.state.terminals.activeSessionId == restored[1])
	}

	@Test("a new tab opens in the pane with the keyboard, and selecting a tab shows it in its own pane")
	func tabsStayInTheirPane() async throws {
		let one = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let store = makeStore(sessions: [one], panes: [one])

		await store.send(.terminals(.splitRequested))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)
		await store.send(.terminals(.newTabRequested))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)
		let ids = store.state.terminals.sessions.map(\.id)
		try #require(ids.count == 3)
		#expect(store.state.terminals.panes.map(\.tabs) == [[ids[0]], [ids[1], ids[2]]])
		#expect(store.state.terminals.shownSessionIds == [ids[0], ids[2]])

		await store.send(.terminals(.paneFocused(sessionId: ids[0])))
		await store.send(.terminals(.selectTab(sessionId: ids[1])))
		#expect(store.state.terminals.shownSessionIds == [ids[0], ids[1]])
		#expect(store.state.terminals.activeSessionId == ids[1])
	}

	// ⌘F is the repository list's shortcut, registered whether or not the panel is up, so the
	// list's reducer is what hands it to the pane with the keyboard.
	@Test("⌘F opens the find bar of the pane with the keyboard")
	func findShortcutReachesTheActivePane() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let found = LockIsolated<[UUID]>([])
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])
		store.dependencies[TerminalPanesClient.self].find = { command, sessionId in
			#expect(command == .show)
			found.withValue { $0.append(sessionId) }
		}

		await store.send(.terminals(.paneFocused(sessionId: beta.id)))
		await store.send(.view(.terminalFindRequested))
		await store.receive(\.terminals.findRequested)
		await store.finish()

		#expect(found.value == [beta.id])
	}

	@Test("a file from before the panel could split restores one terminal on screen")
	func legacyArchiveRestoresSinglePane() throws {
		let legacy = Data("""
		{"tabs":[{"repositoryPath":"/repos/alpha","directory":"/repos/alpha","tabIndex":1,\
		"isRepositoryCurrentTab":true,"isOnScreen":true}]}
		""".utf8)

		let decoded = try JSONDecoder().decode(SavedTerminalTabs.self, from: legacy)

		#expect(decoded.tabs.first?.paneIndex == nil)
	}
}
