import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// Covers dragging a terminal tab onto another tab of the same pane. These tests start
// where `TerminalPanelView` hands the dropped session id to the reducer; the drag itself is
// AppKit's and is not observable from a unit test (see `View.reorderable`).
@Suite("Terminal tab reordering")
@MainActor
struct TerminalTabReorderTests {
	/// The panel open on `active`'s repository: one pane with that repository's tabs in the order
	/// `sessions` has them.
	private func terminals(_ sessions: [TerminalSession], active: TerminalSession) -> TerminalTabs {
		TerminalTabs(
			sessions: IdentifiedArray(uniqueElements: sessions),
			panes: [
				TerminalPane(
					shown: active.id,
					tabs: sessions.filter { $0.repositoryPath == active.repositoryPath }.map(\.id)
				)
			],
			isPanelVisible: true,
			lastActiveSessionByRepo: [active.repositoryPath: active.id]
		)
	}

	private func makeStore(
		sessions: [TerminalSession],
		active: TerminalSession
	) -> TestStoreOf<RepositoryListReducer> {
		var state = RepositoryListReducer.State()
		state.terminals = terminals(sessions, active: active)
		state.terminalLayout = TerminalLayoutReducer.State()
		return TestStore(initialState: state) {
			RepositoryListReducer()
		}
	}

	@Test("a tab dropped on one to its left takes that one's place")
	func dropOnEarlierTabMovesItLeft() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let three = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeStore(sessions: [one, two, three], active: one)

		await store.send(.terminals(.moveTab(sessionId: three.id, ontoSessionId: one.id))) {
			$0.terminals = terminals([three, one, two], active: one)
		}
	}

	@Test("a tab dropped on one to its right takes that one's place")
	func dropOnLaterTabMovesItRight() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let three = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeStore(sessions: [one, two, three], active: one)

		await store.send(.terminals(.moveTab(sessionId: one.id, ontoSessionId: two.id))) {
			$0.terminals = terminals([two, one, three], active: one)
		}
	}

	@Test("moving a tab keeps its number and leaves the active tab alone")
	func moveKeepsTabIndexAndActiveTab() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: two)

		await store.send(.terminals(.moveTab(sessionId: two.id, ontoSessionId: one.id))) {
			$0.terminals = terminals([two, one], active: two)
		}
		#expect(store.state.terminals.sessions.map(\.tabIndex) == [2, 1])
		#expect(store.state.terminals.activeSessionId == two.id)
	}

	@Test("other repositories' tabs keep their order around the moved one")
	func moveLeavesOtherRepositoriesUntouched() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [alphaOne, beta, alphaTwo], active: alphaOne)

		await store.send(.terminals(.moveTab(sessionId: alphaTwo.id, ontoSessionId: alphaOne.id))) {
			$0.terminals = terminals([alphaTwo, alphaOne, beta], active: alphaOne)
		}
		let alphaOrder = store.state.terminals.sessions
			.filter { $0.repositoryPath == "/repos/alpha" }
			.map(\.id)
		#expect(alphaOrder == [alphaTwo.id, alphaOne.id])
	}

	// MARK: - Refused drops

	@Test("a tab dropped on a tab of another repository is ignored")
	func dropAcrossRepositoriesIsANoOp() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let store = makeStore(sessions: [alpha, beta], active: alpha)

		await store.send(.terminals(.moveTab(sessionId: beta.id, ontoSessionId: alpha.id)))
	}

	@Test("a tab dropped on itself, or an id that names no tab, changes nothing")
	func dropOnItselfOrUnknownIsANoOp() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: one)

		await store.send(.terminals(.moveTab(sessionId: one.id, ontoSessionId: one.id)))
		await store.send(.terminals(.moveTab(sessionId: UUID(), ontoSessionId: one.id)))
		await store.send(.terminals(.moveTab(sessionId: one.id, ontoSessionId: UUID())))
	}
}
