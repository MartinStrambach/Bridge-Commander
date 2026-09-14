import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// Switching repositories in the terminal panel used to always land on the repository's
// first tab, because `.selectRepo` resolved the session with `first(where: repositoryPath)`.
// The layout now remembers the tab each repository was left on.
@Suite("Terminal per-repository tab persistence")
@MainActor
struct TerminalTabPersistenceTests {
	private func state(
		sessions: [TerminalSession],
		activeRepositoryPath: String,
		activeSessionId: UUID
	) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State(
			activeRepositoryPath: activeRepositoryPath,
			activeSessionId: activeSessionId
		)
		layout.lastActiveSessionByRepo[activeRepositoryPath] = activeSessionId
		state.terminalLayout = layout
		return state
	}

	@Test("selecting a tab records it as the repository's current tab")
	func selectTabRemembersTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(
			initialState: state(
				sessions: [alphaOne, alphaTwo],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alphaOne.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.selectTab(sessionId: alphaTwo.id))) {
			$0.terminalLayout?.activeSessionId = alphaTwo.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = alphaTwo.id
		}
	}

	@Test("returning to a repository reopens the tab it was left on, not its first tab")
	func returningRestoresLastActiveTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = TestStore(
			initialState: state(
				sessions: [alphaOne, alphaTwo, beta],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alphaOne.id
			)
		) {
			RepositoryListReducer()
		}

		// Alpha, tab 2 → beta → back to alpha.
		await store.send(.terminalLayout(.selectTab(sessionId: alphaTwo.id))) {
			$0.terminalLayout?.activeSessionId = alphaTwo.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = alphaTwo.id
		}
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminalLayout?.activeRepositoryPath = "/repos/beta"
			$0.terminalLayout?.activeSessionId = beta.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = beta.id
		}
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminalLayout?.activeRepositoryPath = "/repos/alpha"
			$0.terminalLayout?.activeSessionId = alphaTwo.id
		}
		// No session was spawned to serve the switches.
		#expect(store.state.terminalSessions.count == 3)
	}

	@Test("a repository visited for the first time opens on its first existing tab")
	func firstVisitUsesFirstTab() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		let store = TestStore(
			initialState: state(
				sessions: [alpha, betaOne, betaTwo],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alpha.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminalLayout?.activeRepositoryPath = "/repos/beta"
			$0.terminalLayout?.activeSessionId = betaOne.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = betaOne.id
		}
	}

	@Test("a new tab becomes the repository's remembered tab")
	func newTabIsRemembered() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = TestStore(
			initialState: state(
				sessions: [alpha, beta],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alpha.id
			)
		) {
			RepositoryListReducer()
		}

		// The new session's id is a fresh UUID, so assert against it instead of predicting it.
		store.exhaustivity = .off
		await store.send(.terminalLayout(.newTabRequested))
		let created = store.state.terminalSessions[2]
		#expect(store.state.terminalLayout?.activeSessionId == created.id)
		#expect(store.state.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] == created.id)

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta")))
		#expect(store.state.terminalLayout?.activeSessionId == beta.id)

		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		#expect(store.state.terminalLayout?.activeSessionId == created.id)
		#expect(store.state.terminalSessions.count == 3)
	}

	@Test("closing the remembered tab forgets it, so the repository falls back to its first tab")
	func killingRememberedTabFallsBack() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = TestStore(
			initialState: state(
				sessions: [alphaOne, alphaTwo, beta],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alphaTwo.id
			)
		) {
			RepositoryListReducer()
		}
		await store.send(.terminalLayout(.killTab(sessionId: alphaTwo.id))) {
			$0.terminalSessions.remove(id: alphaTwo.id)
			$0.terminalLayout?.activeSessionId = alphaOne.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = alphaOne.id
		}
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminalLayout?.activeRepositoryPath = "/repos/beta"
			$0.terminalLayout?.activeSessionId = beta.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = beta.id
		}
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminalLayout?.activeRepositoryPath = "/repos/alpha"
			$0.terminalLayout?.activeSessionId = alphaOne.id
		}
	}

	@Test("killing a repository's tabs clears its memory, so reopening it starts a fresh session")
	func killRepoClearsMemory() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = TestStore(
			initialState: state(
				sessions: [alpha, beta],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alpha.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.killRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminalSessions.remove(id: alpha.id)
			$0.terminalLayout?.activeRepositoryPath = "/repos/beta"
			$0.terminalLayout?.activeSessionId = beta.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = nil
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/beta"] = beta.id
		}

		// Reopening alpha must not resurrect the killed session's id.
		store.exhaustivity = .off
		await store.send(.terminalLayout(.selectRepo(repositoryPath: "/repos/alpha")))
		let created = store.state.terminalSessions[1]
		#expect(created.repositoryPath == "/repos/alpha")
		#expect(created.id != alpha.id)
		#expect(store.state.terminalLayout?.activeSessionId == created.id)
		#expect(store.state.terminalSessions.count == 2)
	}
}
