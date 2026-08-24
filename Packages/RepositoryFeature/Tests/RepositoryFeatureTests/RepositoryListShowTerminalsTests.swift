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
}
