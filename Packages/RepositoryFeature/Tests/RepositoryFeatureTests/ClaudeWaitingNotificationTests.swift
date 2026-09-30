import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Claude waiting notifications")
@MainActor
struct ClaudeWaitingNotificationTests {
	@Test("posts when a session starts waiting and the panel is closed")
	func postsWhenPanelClosed() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let posted = LockIsolated<[UUID]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[ClaudeNotificationClient.self].post = { id, _, _ in posted.withValue { $0.append(id) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value == [session.id])
	}

	@Test("does not post for the tab on screen while the app is active")
	func skipsVisibleTab() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		state.terminalLayout = TerminalLayoutReducer.State()
		state.terminalLayout?.activate(session)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[ClaudeNotificationClient.self].isAppActive = { true }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
	}

	@Test("posts for the tab on screen while the app is in the background")
	func postsForVisibleTabInBackground() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		state.terminalLayout = TerminalLayoutReducer.State()
		state.terminalLayout?.activate(session)
		let posted = LockIsolated<[UUID]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[ClaudeNotificationClient.self].isAppActive = { false }
			$0[ClaudeNotificationClient.self].post = { id, _, _ in posted.withValue { $0.append(id) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value == [session.id])
	}

	@Test("withdraws the notification once the session is back at work")
	func removesWhenActiveAgain() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .waitingForInput
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let removed = LockIsolated<[UUID]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[ClaudeNotificationClient.self].remove = { id in removed.withValue { $0.append(id) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .active))) {
			$0.terminalSessions[id: session.id]?.status = .active
		}
		#expect(removed.value == [session.id])
	}

	@Test("clicking the notification opens the panel on that session")
	func tapOpensSession() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		var state = RepositoryListReducer.State()
		state.terminalSessions = [first, second]
		let activated = LockIsolated(false)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[ClaudeNotificationClient.self].activateApp = { activated.setValue(true) }
		}
		store.exhaustivity = .off

		await store.send(.claudeNotificationTapped(sessionId: second.id))
		#expect(store.state.terminalLayout?.activeSessionId == second.id)
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/alpha")
		await store.finish()
		#expect(activated.value)
	}
}
