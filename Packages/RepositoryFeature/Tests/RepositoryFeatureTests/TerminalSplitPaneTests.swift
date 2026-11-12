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

	private func makeStore(
		sessions: [TerminalSession],
		panes: [TerminalSession]
	) -> TestStoreOf<RepositoryListReducer> {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State()
		layout.activate(panes[0])
		if panes.count > 1 {
			layout.splitSessionIds = panes.map(\.id)
		}
		state.terminalLayout = layout
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}
		// A split makes a session with an id of its own, so the tests read the state afterwards
		// instead of spelling it out.
		store.exhaustivity = .off
		return store
	}

	@Test("⌘D opens a new tab of the active repository beside it, where its shell is")
	func splitOpensNewTabBesideActive() async throws {
		let one = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let store = makeStore(sessions: [one], panes: [one])

		await store.send(.terminalLayout(.splitRequested(directory: "/repos/alpha/Sources")))

		let added = try #require(store.state.terminalSessions.last)
		#expect(store.state.terminalSessions.count == 2)
		#expect(added.repositoryPath == Self.alpha)
		#expect(added.tabIndex == 2)
		#expect(added.startingDirectory == "/repos/alpha/Sources")
		#expect(added.startupCommand == nil)
		#expect(store.state.terminalLayout?.paneSessionIds == [one.id, added.id])
		#expect(store.state.terminalLayout?.activeSessionId == added.id)
	}

	@Test("with three panes ⌘D opens nothing")
	func splitStopsAtThreePanes() async {
		let sessions = (1 ... 3).map { TerminalSession(repositoryPath: Self.alpha, tabIndex: $0) }
		let store = makeStore(sessions: sessions, panes: sessions)

		await store.send(.terminalLayout(.splitRequested(directory: nil)))

		#expect(store.state.terminalSessions.count == 3)
	}

	@Test("a repository opened in the split shows the tab it was last on")
	func openRepoInSplitShowsItsCurrentTab() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let betaOne = TerminalSession(repositoryPath: Self.beta, tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: Self.beta, tabIndex: 2)
		let store = makeStore(sessions: [alpha, betaOne, betaTwo], panes: [alpha])
		await store.send(.terminalLayout(.selectTab(sessionId: betaTwo.id)))
		await store.send(.terminalLayout(.selectTab(sessionId: alpha.id)))

		await store.send(.terminalLayout(.openRepoInSplit(repositoryPath: Self.beta)))

		#expect(store.state.terminalSessions.count == 3)
		#expect(store.state.terminalLayout?.paneSessionIds == [alpha.id, betaTwo.id])
		#expect(store.state.terminalLayout?.activeRepositoryPath == Self.beta)
	}

	@Test("a repository with no terminal gets its first one, opened in the split")
	func openRepoInSplitOpensFirstTab() async throws {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let store = makeStore(sessions: [alpha], panes: [alpha])

		await store.send(.terminalLayout(.openRepoInSplit(repositoryPath: Self.beta)))

		let added = try #require(store.state.terminalSessions.last)
		#expect(added.repositoryPath == Self.beta)
		#expect(store.state.terminalLayout?.paneSessionIds == [alpha.id, added.id])
	}

	@Test("selecting a repository in the sidebar changes the active pane only")
	func selectRepoReplacesActivePane() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let gamma = TerminalSession(repositoryPath: "/repos/gamma")
		let store = makeStore(sessions: [alpha, beta, gamma], panes: [alpha, beta])

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/gamma")))
		#expect(store.state.terminalLayout?.paneSessionIds == [gamma.id, beta.id])

		// One already on screen keeps its pane.
		await store.send(.terminalLayout(.selectRepo(repositoryPath: Self.beta)))
		#expect(store.state.terminalLayout?.paneSessionIds == [gamma.id, beta.id])
		#expect(store.state.terminalLayout?.activeSessionId == beta.id)
	}

	@Test("⌘W beside another pane closes the repository's last tab without asking")
	func closeActiveBesideAnotherPane() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])

		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab)

		#expect(store.state.alert == nil)
		#expect(store.state.terminalSessions.map(\.id) == [beta.id])
		#expect(store.state.terminalLayout?.activeSessionId == beta.id)
		#expect(store.state.terminalLayout?.splitSessionIds == [])
	}

	@Test("taking a pane out of the split leaves its terminal open as a tab")
	func removingPaneKeepsTerminalRunning() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])

		await store.send(.terminalLayout(.closePane(sessionId: alpha.id)))

		#expect(store.state.terminalSessions.count == 2)
		#expect(store.state.terminalLayout?.paneSessionIds == [beta.id])
		#expect(store.state.terminalLayout?.activeRepositoryPath == Self.beta)
	}

	@Test("a run from a simulator pane beside another repository's terminal runs in its own repository")
	func runGoesToTheSimulatorsRepository() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		var state = RepositoryListReducer.State()
		state.terminalSessions = [alpha, beta]
		var layout = TerminalLayoutReducer.State()
		layout.activate(beta)
		layout.splitSessionIds = [beta.id, alpha.id]
		state.terminalLayout = layout
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "run", title: "App", repositoryPath: Self.alpha)))))

		#expect(store.state.terminalSessions.last?.repositoryPath == Self.alpha)
		#expect(store.state.terminalSessions.last?.isRunTab == true)
		#expect(store.state.terminalLayout?.activeSessionId == beta.id)
	}

	@Test("hiding the panel keeps the split for when it is shown again")
	func hidingKeepsSplit() async throws {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeStore(sessions: [alpha, beta], panes: [alpha, beta])

		await store.send(.terminalLayout(.hideTerminalMode))
		#expect(store.state.terminalLayout == nil)

		await store.send(.view(.showTerminalsRequested))
		#expect(store.state.terminalLayout?.paneSessionIds == [alpha.id, beta.id])
		#expect(store.state.terminalLayout?.activeSessionId == alpha.id)

		// A terminal opened from outside the split takes the pane that had the keyboard.
		await store.send(.terminalLayout(.hideTerminalMode))
		await store.send(.view(.openHomeTerminalButtonTapped))
		let home = try #require(store.state.terminalSessions.last)
		#expect(store.state.terminalLayout?.paneSessionIds == [home.id, beta.id])
	}

	@Test("the split is saved with the tabs and comes back in its order")
	func archiveKeepsSplit() async throws {
		var alpha = TerminalSession(repositoryPath: Self.alpha)
		var beta = TerminalSession(repositoryPath: Self.beta)
		alpha.status = .active
		beta.status = .active
		var layout = TerminalLayoutReducer.State()
		layout.activate(beta)
		layout.splitSessionIds = [beta.id, alpha.id]

		let saved = SavedTerminalTabs(sessions: [alpha, beta], layout: layout, panes: [:])
		#expect(saved.tabs.map(\.paneIndex) == [1, 0])

		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		await store.send(.restoreTerminalTabs)

		let restored = store.state.terminalSessions
		#expect(store.state.terminalLayout?.paneSessionIds == [restored[1].id, restored[0].id])
		#expect(store.state.terminalLayout?.activeSessionId == restored[1].id)
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
		var layout = TerminalLayoutReducer.State()
		layout.activate(two)
		layout.splitSessionIds = [two.id, three.id]
		layout.splitTabIds = [[one.id, two.id], [three.id]]

		let saved = SavedTerminalTabs(sessions: [one, two, three], layout: layout, panes: [:])
		#expect(saved.tabs.map(\.paneIndex) == [0, 0, 1])
		#expect(saved.tabs.map(\.isPaneCurrentTab) == [false, true, true])

		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		await store.send(.restoreTerminalTabs)

		let restored = store.state.terminalSessions.map(\.id)
		#expect(store.state.terminalLayout?.paneSessionIds == [restored[1], restored[2]])
		#expect(store.state.terminalLayout?.splitTabIds == [[restored[0], restored[1]], [restored[2]]])
		#expect(store.state.terminalLayout?.activeSessionId == restored[1])
	}

	@Test("a new tab opens in the pane with the keyboard, and selecting a tab shows it in its own pane")
	func tabsStayInTheirPane() async throws {
		let one = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let store = makeStore(sessions: [one], panes: [one])

		await store.send(.terminalLayout(.splitRequested(directory: nil)))
		await store.send(.terminalLayout(.newTabRequested))
		let ids = store.state.terminalSessions.map(\.id)
		#expect(store.state.terminalLayout?.splitTabIds == [[ids[0]], [ids[1], ids[2]]])
		#expect(store.state.terminalLayout?.paneSessionIds == [ids[0], ids[2]])

		await store.send(.terminalLayout(.paneFocused(sessionId: ids[0])))
		await store.send(.terminalLayout(.selectTab(sessionId: ids[1])))
		#expect(store.state.terminalLayout?.paneSessionIds == [ids[0], ids[1]])
		#expect(store.state.terminalLayout?.activeSessionId == ids[1])
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
