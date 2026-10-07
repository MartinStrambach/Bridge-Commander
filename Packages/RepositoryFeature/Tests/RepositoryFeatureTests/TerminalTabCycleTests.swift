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
	private func makeStore(
		sessions: [TerminalSession],
		active: TerminalSession
	) -> TestStoreOf<RepositoryListReducer> {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State(
			activeRepositoryPath: active.repositoryPath,
			activeSessionId: active.id
		)
		layout.lastActiveSessionByRepo[active.repositoryPath] = active.id
		layout.recentSessionIds = [active.id]
		state.terminalLayout = layout
		return TestStore(initialState: state) {
			RepositoryListReducer()
		}
	}

	@Test("⌃Tab moves to the next tab and wraps from the last to the first")
	func forwardWraps() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: one)

		await store.send(.terminalLayout(.cycleTabRequested(forward: true))) {
			$0.terminalLayout?.activeSessionId = two.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = two.id
			$0.terminalLayout?.recentSessionIds = [one.id, two.id]
		}
		await store.send(.terminalLayout(.cycleTabRequested(forward: true))) {
			$0.terminalLayout?.activeSessionId = one.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = one.id
			$0.terminalLayout?.recentSessionIds = [two.id, one.id]
		}
	}

	@Test("⌃⇧Tab moves to the previous tab and wraps from the first to the last")
	func backwardWraps() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let three = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeStore(sessions: [one, two, three], active: one)

		await store.send(.terminalLayout(.cycleTabRequested(forward: false))) {
			$0.terminalLayout?.activeSessionId = three.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = three.id
			$0.terminalLayout?.recentSessionIds = [one.id, three.id]
		}
		await store.send(.terminalLayout(.cycleTabRequested(forward: false))) {
			$0.terminalLayout?.activeSessionId = two.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = two.id
			$0.terminalLayout?.recentSessionIds = [one.id, three.id, two.id]
		}
	}

	@Test("cycling follows the tab bar's order and skips other repositories' tabs")
	func followsBarOrderWithinRepository() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		// Tab 2 was dragged in front of tab 1, so the bar reads "Terminal 2, Terminal 1".
		let store = makeStore(sessions: [alphaTwo, beta, alphaOne], active: alphaTwo)

		await store.send(.terminalLayout(.cycleTabRequested(forward: true))) {
			$0.terminalLayout?.activeSessionId = alphaOne.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = alphaOne.id
			$0.terminalLayout?.recentSessionIds = [alphaTwo.id, alphaOne.id]
		}
		await store.send(.terminalLayout(.cycleTabRequested(forward: true))) {
			$0.terminalLayout?.activeSessionId = alphaTwo.id
			$0.terminalLayout?.lastActiveSessionByRepo["/repos/alpha"] = alphaTwo.id
			$0.terminalLayout?.recentSessionIds = [alphaOne.id, alphaTwo.id]
		}
	}

	@Test("a repository with a single tab stays on it")
	func singleTabIsANoOp() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = makeStore(sessions: [alpha, beta], active: alpha)

		await store.send(.terminalLayout(.cycleTabRequested(forward: true)))
		await store.send(.terminalLayout(.cycleTabRequested(forward: false)))
	}
}
