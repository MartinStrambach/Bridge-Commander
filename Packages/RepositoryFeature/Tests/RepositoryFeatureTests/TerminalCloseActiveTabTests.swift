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
//
// A closed tab's shell is hung up by `TerminalPanesClient.kill`, called with the sessions that
// left the state. The tests that close something record what it was given; the ones that close
// nothing leave it unimplemented, so a shell hung up by mistake fails them.
@Suite("Terminal ⌘W close active tab")
@MainActor
struct TerminalCloseActiveTabTests {
	private static let alpha = "/repos/alpha"
	private static let beta = "/repos/beta"
	private static let gamma = "/repos/gamma"

	/// What `TerminalPanesClient.kill` was called with, one entry per call.
	private let killed = LockIsolated<[Set<UUID>]>([])

	/// The panel open on the last of `shown`, having shown the ones before it in turn — through
	/// `show`, so the per-repository tab memory holds what it would in the app: closing a tab
	/// has to leave that memory pointing at the tab that took over, not at the closed one.
	private func makeState(
		sessions: [TerminalSession],
		shown: [TerminalSession]
	) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		var terminals = TerminalTabs(sessions: IdentifiedArray(uniqueElements: sessions))
		for session in shown {
			terminals.show(session)
		}
		terminals.showPanel()
		state.terminals = terminals
		state.terminalLayout = TerminalLayoutReducer.State()
		return state
	}

	private func makeStore(_ state: RepositoryListReducer.State) -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: state) {
			RepositoryListReducer()
		}
	}

	/// A store whose closed sessions are recorded in `killed`.
	private func makeClosingStore(_ state: RepositoryListReducer.State) -> TestStoreOf<RepositoryListReducer> {
		TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalPanesClient.self].kill = { [killed] ids in
				killed.withValue { $0.append(Set(ids)) }
			}
		}
	}

	@Test("closes the active tab and activates the next one, on every press")
	func closesEveryTabDownToTheLastOne() async {
		let first = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let second = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		let third = TerminalSession(repositoryPath: Self.alpha, tabIndex: 3)
		let store = makeClosingStore(makeState(sessions: [first, second, third], shown: [first]))

		await store.send(.terminals(.closeActiveTabRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [second, third],
				panes: [TerminalPane(shown: second.id, tabs: [second.id, third.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: second.id],
				recentSessionIds: [second.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[first.id]])

		// The regression: a second press has to reach the tab that is active *now*.
		await store.send(.terminals(.closeActiveTabRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [third],
				panes: [TerminalPane(shown: third.id, tabs: [third.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: third.id],
				recentSessionIds: [third.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[first.id], [second.id]])
	}

	@Test("closing a middle tab activates the tab to its right, not the first one")
	func activatesTheTabToTheRight() async {
		let first = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let second = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		let third = TerminalSession(repositoryPath: Self.alpha, tabIndex: 3)
		let store = makeClosingStore(makeState(sessions: [first, second, third], shown: [second]))

		await store.send(.terminals(.closeActiveTabRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [first, third],
				panes: [TerminalPane(shown: third.id, tabs: [first.id, third.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: third.id],
				recentSessionIds: [third.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[second.id]])
	}

	@Test("closing the rightmost tab falls back to the new last tab")
	func activatesTheNewLastTab() async {
		let first = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let second = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		let third = TerminalSession(repositoryPath: Self.alpha, tabIndex: 3)
		let store = makeClosingStore(makeState(sessions: [first, second, third], shown: [third]))

		await store.send(.terminals(.closeActiveTabRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [first, second],
				panes: [TerminalPane(shown: second.id, tabs: [first.id, second.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: second.id],
				recentSessionIds: [second.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[third.id]])
	}

	@Test("another repo's tabs do not shift which tab takes over")
	func neighbourIsScopedToTheOpenedRepository() async {
		let beta = TerminalSession(repositoryPath: Self.beta)
		let first = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let second = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		// Interleaved on purpose: the place of the closed tab has to be read among the pane's
		// tabs only, not among every session in state.
		let store = makeClosingStore(makeState(sessions: [beta, first, second], shown: [first]))

		await store.send(.terminals(.closeActiveTabRequested)) {
			$0.terminals = TerminalTabs(
				sessions: [beta, second],
				panes: [TerminalPane(shown: second.id, tabs: [second.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.alpha: second.id],
				recentSessionIds: [second.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[first.id]])
	}

	@Test("closing a repository's last tab moves to the repository most recently on screen")
	func lastTabFallsBackToTheMostRecentRepository() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let gamma = TerminalSession(repositoryPath: Self.gamma)
		// Beta is first in line by position, but gamma was on screen more recently.
		let store = makeClosingStore(makeState(sessions: [alpha, beta, gamma], shown: [beta, gamma, alpha]))

		await store.send(.terminals(.killTab(sessionId: alpha.id))) {
			$0.terminals = TerminalTabs(
				sessions: [beta, gamma],
				panes: [TerminalPane(shown: gamma.id, tabs: [gamma.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.beta: beta.id, Self.gamma: gamma.id],
				recentSessionIds: [beta.id, gamma.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[alpha.id]])
	}

	@Test("closing the repository on screen moves to the repository most recently on screen")
	func killRepoFallsBackToTheMostRecentRepository() async {
		let alphaOne = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let gamma = TerminalSession(repositoryPath: Self.gamma)
		let store = makeClosingStore(makeState(
			sessions: [beta, gamma, alphaOne, alphaTwo],
			shown: [beta, gamma, alphaOne, alphaTwo]
		))

		await store.send(.terminals(.killRepo(repositoryPath: Self.alpha))) {
			$0.terminals = TerminalTabs(
				sessions: [beta, gamma],
				panes: [TerminalPane(shown: gamma.id, tabs: [gamma.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.beta: beta.id, Self.gamma: gamma.id],
				recentSessionIds: [beta.id, gamma.id]
			)
		}
		await store.finish()
		// Both of the repository's shells, in one call, and no one else's.
		#expect(killed.value == [[alphaOne.id, alphaTwo.id]])
	}

	// The last tab of a repo while another repo still has terminals: closing it could mean
	// "leave this repo" or "I'm done, quit" — the two readings are far enough apart to ask.
	@Test("asks on the repo's last tab while another repo still has terminals")
	func asksBeforeClosingTheLastTab() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta, tabIndex: 1)
		let betaSecond = TerminalSession(repositoryPath: Self.beta, tabIndex: 2)
		let store = makeStore(makeState(sessions: [alpha, beta, betaSecond], shown: [alpha]))

		await store.send(.terminals(.closeActiveTabRequested))
		await store.receive(\.terminals.delegate.lastTabCloseRequested) {
			// Two sessions, but one other repository — the question counts repositories.
			$0.alert = RepositoryListReducer.lastTabAlert(sessionId: alpha.id, otherRepoCount: 1)
		}
	}

	@Test("counts the other repositories, not their tabs")
	func countsOtherRepositories() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let gamma = TerminalSession(repositoryPath: Self.gamma)
		let store = makeStore(makeState(sessions: [alpha, beta, gamma], shown: [alpha]))

		await store.send(.terminals(.closeActiveTabRequested))
		await store.receive(\.terminals.delegate.lastTabCloseRequested) {
			$0.alert = RepositoryListReducer.lastTabAlert(sessionId: alpha.id, otherRepoCount: 2)
		}
	}

	@Test("\"Close Tab Only\" closes the last tab and moves to the other repo's session")
	func closeTabOnlyClosesTheLastTab() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let beta = TerminalSession(repositoryPath: Self.beta)
		let store = makeClosingStore(makeState(sessions: [alpha, beta], shown: [alpha]))

		await store.send(.terminals(.closeActiveTabRequested))
		await store.receive(\.terminals.delegate.lastTabCloseRequested) {
			$0.alert = RepositoryListReducer.lastTabAlert(sessionId: alpha.id, otherRepoCount: 1)
		}
		// Asking closes nothing.
		#expect(killed.value == [])

		await store.send(.alert(.presented(.closeLastTabConfirmed(sessionId: alpha.id)))) {
			$0.alert = nil
			$0.terminals = TerminalTabs(
				sessions: [beta],
				panes: [TerminalPane(shown: beta.id, tabs: [beta.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: [Self.beta: beta.id],
				recentSessionIds: [beta.id]
			)
		}
		await store.finish()
		#expect(killed.value == [[alpha.id]])
	}

	// Nothing else is running, so ⌘W is not registered for this case at all and the question would
	// never be asked — the standard File ▸ Close closes the window instead.
	@Test("leaves the last tab of the only repo alone, so ⌘W closes the window instead")
	func ignoresTheLastTabOfTheOnlyRepository() async {
		let alpha = TerminalSession(repositoryPath: Self.alpha)
		let store = makeStore(makeState(sessions: [alpha], shown: [alpha]))

		await store.send(.terminals(.closeActiveTabRequested))
	}

	@Test("does nothing when the active session has already been killed")
	func ignoresAStaleActiveSession() async {
		let first = TerminalSession(repositoryPath: Self.alpha, tabIndex: 1)
		let second = TerminalSession(repositoryPath: Self.alpha, tabIndex: 2)
		// A pane showing a session that is no longer among the open ones.
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(
			sessions: [first, second],
			panes: [TerminalPane(shown: UUID(), tabs: [first.id, second.id])],
			isPanelVisible: true
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = makeStore(state)

		await store.send(.terminals(.closeActiveTabRequested))
	}
}
