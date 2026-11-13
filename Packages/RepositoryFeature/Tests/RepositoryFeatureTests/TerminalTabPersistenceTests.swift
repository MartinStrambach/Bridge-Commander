import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// Switching repositories in the terminal panel used to always land on the repository's
// first tab, because `.selectRepo` resolved the session with `first(where: repositoryPath)`.
// `TerminalTabs` now remembers the tab each repository was left on.
@Suite("Terminal per-repository tab persistence")
@MainActor
struct TerminalTabPersistenceTests {
	/// The panel open on one pane showing `active`, with its repository's tabs in the bar.
	private func tabs(
		_ sessions: [TerminalSession],
		showing active: TerminalSession,
		lastActiveSessionByRepo: [String: UUID],
		recentSessionIds: [UUID]
	) -> TerminalTabs {
		TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: [
				TerminalPane(
					shown: active.id,
					tabs: sessions.filter { $0.repositoryPath == active.repositoryPath }.map(\.id)
				),
			],
			isPanelVisible: true,
			lastActiveSessionByRepo: lastActiveSessionByRepo,
			recentSessionIds: recentSessionIds
		)
	}

	private func state(sessions: [TerminalSession], active: TerminalSession) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		state.terminals = tabs(
			sessions,
			showing: active,
			lastActiveSessionByRepo: [active.repositoryPath: active.id],
			recentSessionIds: [active.id]
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		return state
	}

	@Test("selecting a tab records it as the repository's current tab")
	func selectTabRemembersTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo], active: alphaOne)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.selectTab(sessionId: alphaTwo.id))) {
			$0.terminals = tabs(
				[alphaOne, alphaTwo],
				showing: alphaTwo,
				lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id],
				recentSessionIds: [alphaOne.id, alphaTwo.id]
			)
		}
	}

	@Test("returning to a repository reopens the tab it was left on, not its first tab")
	func returningRestoresLastActiveTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let sessions = [alphaOne, alphaTwo, beta]
		let store = TestStore(initialState: state(sessions: sessions, active: alphaOne)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		// Alpha, tab 2 → beta → back to alpha.
		await store.send(.terminals(.selectTab(sessionId: alphaTwo.id))) {
			$0.terminals = tabs(
				sessions,
				showing: alphaTwo,
				lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id],
				recentSessionIds: [alphaOne.id, alphaTwo.id]
			)
		}
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminals = tabs(
				sessions,
				showing: beta,
				lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id, "/repos/beta": beta.id],
				recentSessionIds: [alphaOne.id, alphaTwo.id, beta.id]
			)
		}
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = tabs(
				sessions,
				showing: alphaTwo,
				lastActiveSessionByRepo: ["/repos/alpha": alphaTwo.id, "/repos/beta": beta.id],
				recentSessionIds: [alphaOne.id, beta.id, alphaTwo.id]
			)
		}
		// No session was spawned to serve the switches.
		#expect(store.state.terminals.sessions.count == 3)
	}

	@Test("a repository visited for the first time opens on its first existing tab")
	func firstVisitUsesFirstTab() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let betaOne = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let betaTwo = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		let store = TestStore(initialState: state(sessions: [alpha, betaOne, betaTwo], active: alpha)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminals = tabs(
				[alpha, betaOne, betaTwo],
				showing: betaOne,
				lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": betaOne.id],
				recentSessionIds: [alpha.id, betaOne.id]
			)
		}
	}

	@Test("a new tab becomes the repository's remembered tab")
	func newTabIsRemembered() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = TestStore(initialState: state(sessions: [alpha, beta], active: alpha)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}

		// The list builds the session the workspace asks for, with the next id the `uuid`
		// dependency gives out.
		let created = TerminalSession(id: UUID(0), repositoryPath: "/repos/alpha", tabIndex: 2)
		let sessions = [alpha, beta, created]
		await store.send(.terminals(.newTabRequested))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt) {
			$0.terminals = tabs(
				sessions,
				showing: created,
				lastActiveSessionByRepo: ["/repos/alpha": created.id],
				recentSessionIds: [alpha.id, created.id]
			)
		}

		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminals = tabs(
				sessions,
				showing: beta,
				lastActiveSessionByRepo: ["/repos/alpha": created.id, "/repos/beta": beta.id],
				recentSessionIds: [alpha.id, created.id, beta.id]
			)
		}

		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = tabs(
				sessions,
				showing: created,
				lastActiveSessionByRepo: ["/repos/alpha": created.id, "/repos/beta": beta.id],
				recentSessionIds: [alpha.id, beta.id, created.id]
			)
		}
		#expect(store.state.terminals.sessions.count == 3)
	}

	@Test("closing the remembered tab forgets it, so the repository falls back to its first tab")
	func killingRememberedTabFallsBack() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let killed = LockIsolated<[[UUID]]>([])
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo, beta], active: alphaTwo)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalPanesClient.self].kill = { ids in killed.withValue { $0.append(ids) } }
		}
		await store.send(.terminals(.killTab(sessionId: alphaTwo.id))) {
			$0.terminals = tabs(
				[alphaOne, beta],
				showing: alphaOne,
				lastActiveSessionByRepo: ["/repos/alpha": alphaOne.id],
				recentSessionIds: [alphaOne.id]
			)
		}
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/beta"))) {
			$0.terminals = tabs(
				[alphaOne, beta],
				showing: beta,
				lastActiveSessionByRepo: ["/repos/alpha": alphaOne.id, "/repos/beta": beta.id],
				recentSessionIds: [alphaOne.id, beta.id]
			)
		}
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = tabs(
				[alphaOne, beta],
				showing: alphaOne,
				lastActiveSessionByRepo: ["/repos/alpha": alphaOne.id, "/repos/beta": beta.id],
				recentSessionIds: [beta.id, alphaOne.id]
			)
		}
		await store.finish()
		// The closed tab's shell is hung up, and only its.
		#expect(killed.value == [[alphaTwo.id]])
	}

	@Test("killing a repository's tabs clears its memory, so reopening it starts a fresh session")
	func killRepoClearsMemory() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let killed = LockIsolated<[[UUID]]>([])
		let store = TestStore(initialState: state(sessions: [alpha, beta], active: alpha)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalPanesClient.self].kill = { ids in killed.withValue { $0.append(ids) } }
		}

		await store.send(.terminals(.killRepo(repositoryPath: "/repos/alpha"))) {
			$0.terminals = tabs(
				[beta],
				showing: beta,
				lastActiveSessionByRepo: ["/repos/beta": beta.id],
				recentSessionIds: [beta.id]
			)
		}

		// Reopening alpha must not resurrect the killed session: the list is asked for a new one.
		let created = TerminalSession(id: UUID(0), repositoryPath: "/repos/alpha")
		await store.send(.terminals(.selectRepo(repositoryPath: "/repos/alpha")))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt) {
			$0.terminals = tabs(
				[beta, created],
				showing: created,
				lastActiveSessionByRepo: ["/repos/alpha": created.id, "/repos/beta": beta.id],
				recentSessionIds: [beta.id, created.id]
			)
		}
		#expect(created.id != alpha.id)
		await store.finish()
		#expect(killed.value == [[alpha.id]])
	}
}
