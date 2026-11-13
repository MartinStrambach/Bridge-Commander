import ComposableArchitecture
import TerminalFeature
import Testing
@testable import RepositoryFeature

// ⌘⇧§ sends `.view(.showTerminalsRequested)`: it shows the terminal panel again without
// spawning a session — the counterpart to ⌘§ inside TerminalLayoutView, which hides the panel.
// A panel that was hidden comes back as it was; one that has shown nothing yet picks a session.
@Suite("Repository list show-terminals shortcut")
@MainActor
struct RepositoryListShowTerminalsTests {
	@Test("with no sessions there is nothing to show, so the panel stays closed")
	func noSessionsIsNoOp() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested))
	}

	@Test("opens the panel on the existing session without creating another one")
	func opensPanelOnExistingSession() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(sessions: [session])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [session],
				panes: [TerminalPane(shown: session.id, tabs: [session.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": session.id],
				recentSessionIds: [session.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
		#expect(store.state.terminals.sessions == [session])
	}

	@Test("prefers a live session over a lingering failed one")
	func prefersLiveSessionOverFailed() async {
		var failed = TerminalSession(repositoryPath: "/repos/alpha")
		failed.status = .failed("exited (1)")
		let live = TerminalSession(repositoryPath: "/repos/beta")
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(sessions: [failed, live])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [failed, live],
				panes: [TerminalPane(shown: live.id, tabs: [live.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/beta": live.id],
				recentSessionIds: [live.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("falls back to a failed session when none are live, so its retry tab is reachable")
	func fallsBackToFailedSession() async {
		var failed = TerminalSession(repositoryPath: "/repos/alpha")
		failed.status = .failed("exited (1)")
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(sessions: [failed])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [failed],
				panes: [TerminalPane(shown: failed.id, tabs: [failed.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": failed.id],
				recentSessionIds: [failed.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("the pane that opens has every tab of the session's repository")
	func opensWithTheRepositorysTabs() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(sessions: [alphaOne, beta, alphaTwo])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [alphaOne, beta, alphaTwo],
				panes: [TerminalPane(shown: alphaOne.id, tabs: [alphaOne.id, alphaTwo.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": alphaOne.id],
				recentSessionIds: [alphaOne.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("does nothing while the panel is already open")
	func noOpWhilePanelOpen() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(
			sessions: [alpha, beta],
			panes: [TerminalPane(shown: alpha.id, tabs: [alpha.id])],
			isPanelVisible: true
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		// The active tab must not jump to another session.
		await store.send(.view(.showTerminalsRequested))
	}

	// Hiding the panel used to drop its whole state, so the shortcut opened on the first live
	// session in the list. Hiding is now a flag: the panes, the keyboard and the memory stay.
	@Test("reopens on the terminal the user was in before the panel was hidden")
	func reopensOnTheMostRecentSession() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		let shown = TerminalTabs(
			sessions: [alpha, betaOne, betaTwo],
			panes: [TerminalPane(shown: betaTwo.id, tabs: [betaOne.id, betaTwo.id])],
			isPanelVisible: true,
			lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": betaTwo.id],
			recentSessionIds: [betaOne.id, alpha.id, betaTwo.id]
		)
		var state = RepositoryListReducer.State()
		state.terminals = shown
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.terminals(.hidePanelRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [alpha, betaOne, betaTwo],
				panes: [TerminalPane(shown: betaTwo.id, tabs: [betaOne.id, betaTwo.id])],
				isPanelVisible: false,
				lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": betaTwo.id],
				recentSessionIds: [betaOne.id, alpha.id, betaTwo.id]
			)
			$0.terminalLayout = nil
		}
		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = shown
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("a split that was hidden comes back with its panes, their tabs and the keyboard where it was")
	func hiddenSplitComesBackAsItWas() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		let shown = TerminalTabs(
			sessions: [alphaOne, alphaTwo, beta],
			panes: [
				TerminalPane(shown: alphaTwo.id, tabs: [alphaOne.id, alphaTwo.id]),
				TerminalPane(shown: beta.id, tabs: [beta.id]),
			],
			activePaneIndex: 1,
			isPanelVisible: true,
			lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id, "/repos/beta": beta.id],
			recentSessionIds: [alphaOne.id, alphaTwo.id, beta.id]
		)
		var hidden = shown
		hidden.hidePanel()
		#expect(hidden.panes == shown.panes)
		#expect(!hidden.isPanelVisible)
		var state = RepositoryListReducer.State()
		state.terminals = shown
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested))
		await store.send(.terminals(.hidePanelRequested)) {
			$0.terminals = hidden
			$0.terminalLayout = nil
		}
		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = shown
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
		#expect(store.state.terminals.activeSessionId == beta.id)
		#expect(store.state.terminals.shownSessionIds == [alphaTwo.id, beta.id])
	}

	// The choice of a live session is for a panel that has shown nothing. One that was hidden
	// returns to the terminal it was on, failed or not: its retry button is what the user left.
	@Test("a hidden panel comes back on the terminal it showed even when that one has failed")
	func hiddenPanelKeepsItsFailedTerminal() async {
		var failed = TerminalSession(repositoryPath: "/repos/alpha")
		failed.status = .failed("exited (1)")
		let live = TerminalSession(repositoryPath: "/repos/beta")
		let hidden = TerminalTabs(
			sessions: [failed, live],
			panes: [TerminalPane(shown: failed.id, tabs: [failed.id])],
			lastActiveSessionByRepo: ["/repos/alpha": failed.id, "/repos/beta": live.id],
			recentSessionIds: [live.id, failed.id]
		)
		var state = RepositoryListReducer.State()
		state.terminals = hidden
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [failed, live],
				panes: [TerminalPane(shown: failed.id, tabs: [failed.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": failed.id, "/repos/beta": live.id],
				recentSessionIds: [live.id, failed.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("with nothing shown yet, a failed most recent terminal gives way to the most recent live one")
	func reopensOnTheMostRecentLiveSession() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var gamma = TerminalSession(repositoryPath: "/repos/gamma")
		gamma.status = .failed("exited (1)")
		let memory = [
			"/repos/alpha": alpha.id,
			"/repos/beta": beta.id,
			"/repos/gamma": gamma.id,
		]
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(
			sessions: [alpha, beta, gamma],
			lastActiveSessionByRepo: memory,
			recentSessionIds: [alpha.id, beta.id, gamma.id]
		)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [alpha, beta, gamma],
				panes: [TerminalPane(shown: beta.id, tabs: [beta.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: memory,
				recentSessionIds: [alpha.id, gamma.id, beta.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}
}
