import ComposableArchitecture
import TerminalFeature
import Testing
@testable import RepositoryFeature

// ⌘⇧§ sends `.view(.showTerminalsRequested)`: it reopens the terminal panel on an existing
// session without spawning a new one — the counterpart to ⌘§ inside TerminalLayoutView,
// which closes the panel.
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
		state.terminalSessions = [session]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminalLayout = TerminalLayoutReducer.State(
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: session.id
			)
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = session.id
			$0.terminalLayout?.recentSessionIds = [session.id]
		}
		#expect(store.state.terminalSessions == [session])
	}

	@Test("prefers a live session over a lingering failed one")
	func prefersLiveSessionOverFailed() async {
		var failed = TerminalSession(repositoryPath: "/repos/alpha")
		failed.status = .failed("exited (1)")
		let live = TerminalSession(repositoryPath: "/repos/beta")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [failed, live]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminalLayout = TerminalLayoutReducer.State(
				activeRepositoryPath: "/repos/beta",
				activeSessionId: live.id
			)
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = live.id
			$0.terminalLayout?.recentSessionIds = [live.id]
		}
	}

	@Test("falls back to a failed session when none are live, so its retry tab is reachable")
	func fallsBackToFailedSession() async {
		var failed = TerminalSession(repositoryPath: "/repos/alpha")
		failed.status = .failed("exited (1)")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [failed]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.terminalLayout = TerminalLayoutReducer.State(
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: failed.id
			)
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = failed.id
			$0.terminalLayout?.recentSessionIds = [failed.id]
		}
	}

	@Test("does nothing while the panel is already open")
	func noOpWhilePanelOpen() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [alpha, beta]
		state.terminalLayout = TerminalLayoutReducer.State(
			activeRepositoryPath: "/repos/alpha",
			activeSessionId: alpha.id
		)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		// The active tab must not jump to another session.
		await store.send(.view(.showTerminalsRequested))
	}

	// Hiding the panel drops its whole state, tab memory included, so the shortcut used to open
	// on the first live session in the list rather than on the terminal the user had left.
	@Test("reopens on the terminal the user was in before the panel was hidden")
	func reopensOnTheMostRecentSession() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		var state = RepositoryListReducer.State()
		state.terminalSessions = [alpha, betaOne, betaTwo]
		var layout = TerminalLayoutReducer.State()
		layout.activate(betaOne)
		layout.activate(alpha)
		layout.activate(betaTwo)
		state.terminalLayout = layout
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.hideTerminalMode)) {
			$0.hiddenTerminalTabMemory = layout.tabMemory
			$0.terminalLayout = nil
		}
		await store.send(.view(.showTerminalsRequested)) {
			$0.hiddenTerminalTabMemory = nil
			$0.terminalLayout = layout
		}
	}

	@Test("a failed most recent terminal gives way to the most recent live one")
	func reopensOnTheMostRecentLiveSession() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var gamma = TerminalSession(repositoryPath: "/repos/gamma")
		gamma.status = .failed("exited (1)")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [alpha, beta, gamma]
		state.hiddenTerminalTabMemory = TerminalLayoutReducer.State.TabMemory(
			lastActiveSessionByRepo: [
				"/repos/alpha": alpha.id,
				"/repos/beta": beta.id,
				"/repos/gamma": gamma.id,
			],
			recentSessionIds: [alpha.id, beta.id, gamma.id]
		)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.showTerminalsRequested)) {
			$0.hiddenTerminalTabMemory = nil
			$0.terminalLayout = TerminalLayoutReducer.State(
				activeRepositoryPath: "/repos/beta",
				activeSessionId: beta.id
			)
			$0.terminalLayout?.tabMemory = TerminalLayoutReducer.State.TabMemory(
				lastActiveSessionByRepo: [
					"/repos/alpha": alpha.id,
					"/repos/beta": beta.id,
					"/repos/gamma": gamma.id,
				],
				recentSessionIds: [alpha.id, gamma.id, beta.id]
			)
		}
	}
}
