import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
@testable import RepositoryFeature

// Covers dragging a terminal tab onto another tab of the same repository. These tests start
// where `TerminalPanelView` hands the dropped session id to the reducer; the drag itself is
// AppKit's and is not observable from a unit test (see `View.reorderable`).
@Suite("Terminal tab reordering")
@MainActor
struct TerminalTabReorderTests {
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
		state.terminalLayout = layout
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

		await store.send(.terminalLayout(.moveTab(sessionId: three.id, ontoSessionId: one.id))) {
			$0.terminalSessions = IdentifiedArray(uniqueElements: [three, one, two])
		}
	}

	@Test("a tab dropped on one to its right takes that one's place")
	func dropOnLaterTabMovesItRight() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let three = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeStore(sessions: [one, two, three], active: one)

		await store.send(.terminalLayout(.moveTab(sessionId: one.id, ontoSessionId: two.id))) {
			$0.terminalSessions = IdentifiedArray(uniqueElements: [two, one, three])
		}
	}

	@Test("moving a tab keeps its number and leaves the active tab alone")
	func moveKeepsTabIndexAndActiveTab() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: two)

		await store.send(.terminalLayout(.moveTab(sessionId: two.id, ontoSessionId: one.id))) {
			$0.terminalSessions = IdentifiedArray(uniqueElements: [two, one])
		}
		#expect(store.state.terminalSessions.map(\.tabIndex) == [2, 1])
		#expect(store.state.terminalLayout?.activeSessionId == two.id)
	}

	@Test("other repositories' tabs keep their order around the moved one")
	func moveLeavesOtherRepositoriesUntouched() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [alphaOne, beta, alphaTwo], active: alphaOne)

		await store.send(.terminalLayout(.moveTab(sessionId: alphaTwo.id, ontoSessionId: alphaOne.id))) {
			$0.terminalSessions = IdentifiedArray(uniqueElements: [alphaTwo, alphaOne, beta])
		}
		let alphaOrder = store.state.terminalSessions
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

		await store.send(.terminalLayout(.moveTab(sessionId: beta.id, ontoSessionId: alpha.id)))
	}

	@Test("a tab dropped on itself, or an id that names no tab, changes nothing")
	func dropOnItselfOrUnknownIsANoOp() async {
		let one = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let two = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let store = makeStore(sessions: [one, two], active: one)

		await store.send(.terminalLayout(.moveTab(sessionId: one.id, ontoSessionId: one.id)))
		await store.send(.terminalLayout(.moveTab(sessionId: UUID(), ontoSessionId: one.id)))
		await store.send(.terminalLayout(.moveTab(sessionId: one.id, ontoSessionId: UUID())))
	}
}
