import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// Covers ⌃Tab / ⌃⇧Tab from where `TerminalPanelView`'s hidden shortcut buttons hand the
// request to the reducer.
@Suite("Terminal tab cycling")
@MainActor
struct TerminalTabCycleTests {
	/// The panel open on `active`'s repository: one pane with that repository's tabs in the order
	/// `sessions` has them, `recent` being the tabs that have had the keyboard, `active` last.
	private func terminals(
		_ sessions: [TerminalSession],
		active: TerminalSession,
		recent: [TerminalSession]
	) -> TerminalTabs {
		TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: [
				TerminalPane(
					shown: active.id,
					tabs: sessions.filter { $0.repositoryPath == active.repositoryPath }.map(\.id)
				)
			],
			isPanelVisible: true,
			lastActiveSessionByRepo: [active.repositoryPath: active.id],
			recentSessionIds: recent.map(\.id)
		)
	}

	private func makeStore(
		sessions: [TerminalSession],
		active: TerminalSession
	) -> TestStoreOf<RepositoryListReducer> {
		var state = RepositoryListReducer.State()
		state.terminals = terminals(sessions, active: active, recent: [active])
		state.terminalLayout = TerminalLayoutReducer.State()
		return TestStore(initialState: state) {
			RepositoryListReducer()
		}
	}

	@Test("⌃Tab moves to the next tab and wraps from the last to the first")
	func forwardWraps() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: one)

		await store.send(.terminals(.cycleTabRequested(forward: true))) {
			$0.terminals = terminals([one, two], active: two, recent: [one, two])
		}
		await store.send(.terminals(.cycleTabRequested(forward: true))) {
			$0.terminals = terminals([one, two], active: one, recent: [two, one])
		}
	}

	@Test("⌃⇧Tab moves to the previous tab and wraps from the first to the last")
	func backwardWraps() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let three = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeStore(sessions: [one, two, three], active: one)

		await store.send(.terminals(.cycleTabRequested(forward: false))) {
			$0.terminals = terminals([one, two, three], active: three, recent: [one, three])
		}
		await store.send(.terminals(.cycleTabRequested(forward: false))) {
			$0.terminals = terminals([one, two, three], active: two, recent: [one, three, two])
		}
	}

	@Test("cycling follows the tab bar's order and skips other repositories' tabs")
	func followsBarOrderWithinRepository() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		// Tab 2 was dragged in front of tab 1, so the bar reads "Terminal 2, Terminal 1".
		let store = makeStore(sessions: [alphaTwo, beta, alphaOne], active: alphaTwo)

		await store.send(.terminals(.cycleTabRequested(forward: true))) {
			$0.terminals = terminals([alphaTwo, beta, alphaOne], active: alphaOne, recent: [alphaTwo, alphaOne])
		}
		await store.send(.terminals(.cycleTabRequested(forward: true))) {
			$0.terminals = terminals([alphaTwo, beta, alphaOne], active: alphaTwo, recent: [alphaOne, alphaTwo])
		}
	}

	@Test("a repository with a single tab stays on it")
	func singleTabIsANoOp() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = makeStore(sessions: [alpha, beta], active: alpha)

		await store.send(.terminals(.cycleTabRequested(forward: true)))
		await store.send(.terminals(.cycleTabRequested(forward: false)))
	}
}
