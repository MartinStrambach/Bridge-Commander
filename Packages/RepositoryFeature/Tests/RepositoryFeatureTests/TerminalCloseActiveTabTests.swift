import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// ⌘W in the terminal panel. The shortcut names no session on purpose: it used to hand `killTab`
// the id captured when its hidden button was laid out, SwiftUI kept firing that first closure,
// and every press after the first asked to kill a session that had already left the state — so
// the shortcut closed exactly one tab and then went dead. Resolving the active tab here is what
// makes it repeatable, which is what `closesEveryTabDownToTheLastOne` pins.
@Suite("Terminal ⌘W close active tab")
@MainActor
struct TerminalCloseActiveTabTests {
	private func makeState(
		sessions: [TerminalSession],
		activeRepositoryPath: String,
		activeSessionId: UUID?
	) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		state.terminalLayout = TerminalLayoutReducer.State(
			activeRepositoryPath: activeRepositoryPath,
			activeSessionId: activeSessionId
		)
		return state
	}

	@Test("closes the active tab and activates the next one, on every press")
	func closesEveryTabDownToTheLastOne() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let third = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = TestStore(
			initialState: makeState(
				sessions: [first, second, third],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: first.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab) {
			$0.terminalSessions.remove(id: first.id)
			$0.terminalLayout?.activeSessionId = second.id
		}

		// The regression: a second press has to reach the tab that is active *now*.
		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab) {
			$0.terminalSessions.remove(id: second.id)
			$0.terminalLayout?.activeSessionId = third.id
		}
	}

	@Test("closing a middle tab activates the tab to its right, not the first one")
	func activatesTheTabToTheRight() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let third = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = TestStore(
			initialState: makeState(
				sessions: [first, second, third],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: second.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab) {
			$0.terminalSessions.remove(id: second.id)
			$0.terminalLayout?.activeSessionId = third.id
		}
	}

	@Test("closing the rightmost tab falls back to the new last tab")
	func activatesTheNewLastTab() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let third = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = TestStore(
			initialState: makeState(
				sessions: [first, second, third],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: third.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab) {
			$0.terminalSessions.remove(id: third.id)
			$0.terminalLayout?.activeSessionId = second.id
		}
	}

	@Test("another repo's tabs do not shift which tab takes over")
	func neighbourIsScopedToTheOpenedRepository() async {
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(
			// Interleaved on purpose: the index of the closed tab has to be read among alpha's
			// tabs only, not among every session in state.
			initialState: makeState(
				sessions: [beta, first, second],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: first.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
		await store.receive(\.terminalLayout.killTab) {
			$0.terminalSessions.remove(id: first.id)
			$0.terminalLayout?.activeSessionId = second.id
		}
	}

	@Test("leaves the last tab of the repo alone, so ⌘W closes the window instead")
	func ignoresTheLastTab() async {
		let only = TerminalSession(repositoryPath: "/repos/alpha")
		let store = TestStore(
			initialState: makeState(
				sessions: [only],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: only.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
	}

	@Test("counts only the opened repo's tabs, not another repo's")
	func ignoresTabsOfAnotherRepository() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaSecond = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		let store = TestStore(
			initialState: makeState(
				sessions: [alpha, beta, betaSecond],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: alpha.id
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
	}

	@Test("does nothing when the active session has already been killed")
	func ignoresAStaleActiveSession() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(
			initialState: makeState(
				sessions: [first, second],
				activeRepositoryPath: "/repos/alpha",
				activeSessionId: UUID()
			)
		) {
			RepositoryListReducer()
		}

		await store.send(.terminalLayout(.closeActiveTabRequested))
	}
}
