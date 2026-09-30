import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

@Suite("Repository list terminal notifications")
@MainActor
struct RepositoryListNotificationTests {
	@Test("posts when a session starts waiting and the panel is closed")
	func postsWhenPanelClosed() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value == [
			TerminalNotificationContent(sessionId: session.id, title: "alpha", body: "Claude is waiting for your input."),
		])
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
			$0[TerminalNotificationClient.self].isAppActive = { true }
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
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].isAppActive = { false }
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value.map(\.sessionId) == [session.id])
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
			$0[TerminalNotificationClient.self].remove = { id in removed.withValue { $0.append(id) } }
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
			$0[TerminalNotificationClient.self].activateApp = { activated.setValue(true) }
		}
		store.exhaustivity = .off

		await store.send(.terminalNotificationTapped(sessionId: second.id))
		#expect(store.state.terminalLayout?.activeSessionId == second.id)
		#expect(store.state.terminalLayout?.activeRepositoryPath == "/repos/alpha")
		await store.finish()
		#expect(activated.value)
	}

	@Test("posts nothing when terminal notifications are turned off")
	func skipsWhenSettingOff() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		state.$terminalNotifications.withLock { $0 = false }
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		let notification = TerminalNotification(title: nil, body: "build finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification)))
	}

	@Test("a status change that neither starts nor stops waiting posts and withdraws nothing")
	func ignoresTransitionsOutsideWaiting() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .active))) {
			$0.terminalSessions[id: session.id]?.status = .active
		}
		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .failed("exited")))) {
			$0.terminalSessions[id: session.id]?.status = .failed("exited")
		}
	}

	@Test("clicking the notification of a tab that has since closed still brings the app forward")
	func tapForClosedSession() async {
		let activated = LockIsolated(false)
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].activateApp = { activated.setValue(true) }
		}

		await store.send(.terminalNotificationTapped(sessionId: UUID()))
		#expect(activated.value)
	}

	// MARK: - Notifications a program asks for

	@Test("a program's notification marks the session waiting and posts once, with its own text")
	func programNotificationPosts() async {
		var first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		first.status = .active
		var second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		second.status = .active
		var state = RepositoryListReducer.State()
		state.terminalSessions = [first, second]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: "Claude Code", body: "Claude needs your permission to use Bash")
		await store.send(.view(.terminalNotificationReceived(sessionId: second.id, notification: notification))) {
			$0.terminalSessions[id: second.id]?.status = .waitingForInput
		}
		#expect(posted.value == [
			TerminalNotificationContent(
				sessionId: second.id,
				title: "Claude Code",
				subtitle: "alpha · Terminal 2",
				body: "Claude needs your permission to use Bash"
			),
		])
	}

	@Test("an OSC 9 notification, which has no title, is titled with the tab")
	func untitledProgramNotification() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: nil, body: "build finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification))) {
			$0.terminalSessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value == [TerminalNotificationContent(sessionId: session.id, title: "alpha", body: "build finished")])
	}

	@Test("a notification from a session that is gone changes nothing")
	func programNotificationForKilledSession() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		let notification = TerminalNotification(title: nil, body: "late")
		await store.send(.view(.terminalNotificationReceived(sessionId: UUID(), notification: notification)))
	}
}
