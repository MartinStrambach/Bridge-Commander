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
		state.terminals.sessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value == [
			TerminalNotificationContent(sessionId: session.id, title: "alpha", body: "Claude is waiting for your input."),
		])
	}

	@Test("a startup command's first prompt posts nothing, and the next one posts")
	func skipsStartupPrompt() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "claude")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
			$0[TerminalNotificationClient.self].remove = { _ in }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
			$0.terminals.sessions[id: session.id]?.awaitsStartupPrompt = false
		}
		#expect(posted.value.isEmpty)

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .active))) {
			$0.terminals.sessions[id: session.id]?.status = .active
		}
		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value.map(\.sessionId) == [session.id])
	}

	@Test("a program's notification posts even before a startup command's first prompt")
	func programNotificationBeforeStartupPrompt() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "claude")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: nil, body: "build finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
			$0.terminals.sessions[id: session.id]?.awaitsStartupPrompt = false
		}
		#expect(posted.value.map(\.body) == ["build finished"])
	}

	@Test("does not post for the tab on screen while the app is active")
	func skipsVisibleTab() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(
			sessions: [session],
			panes: [TerminalPane(shown: session.id, tabs: [session.id])],
			isPanelVisible: true
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].isAppActive = { true }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
	}

	@Test("posts for the tab on screen while the app is in the background")
	func postsForVisibleTabInBackground() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminals = TerminalTabs(
			sessions: [session],
			panes: [TerminalPane(shown: session.id, tabs: [session.id])],
			isPanelVisible: true
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].isAppActive = { false }
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value.map(\.sessionId) == [session.id])
	}

	@Test("posts for a tab shown in a pane while the panel is hidden, even with the app active")
	func postsForShownTabWhilePanelHidden() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		// Hiding the panel keeps its panes: the tab is still the one its pane shows, but the
		// user cannot see it.
		state.terminals = TerminalTabs(
			sessions: [session],
			panes: [TerminalPane(shown: session.id, tabs: [session.id])],
			isPanelVisible: false
		)
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].isAppActive = { true }
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
		#expect(posted.value.map(\.sessionId) == [session.id])
	}

	@Test("in a split, posts only for a tab that no pane shows while the app is active")
	func splitPostsOnlyForTabsOffScreen() async {
		var alpha = TerminalSession(repositoryPath: "/repos/alpha")
		alpha.status = .active
		var beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 1)
		beta.status = .active
		var betaBehind = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 2)
		betaBehind.status = .active
		var state = RepositoryListReducer.State()
		// The keyboard is in alpha's pane; beta's pane shows its first tab, the second is behind it.
		state.terminals = TerminalTabs(
			sessions: [alpha, beta, betaBehind],
			panes: [
				TerminalPane(shown: alpha.id, tabs: [alpha.id]),
				TerminalPane(shown: beta.id, tabs: [beta.id, betaBehind.id]),
			],
			isPanelVisible: true
		)
		state.terminalLayout = TerminalLayoutReducer.State()
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].isAppActive = { true }
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		// On screen, though its pane does not have the keyboard.
		await store.send(.view(.terminalSessionStatusChanged(sessionId: beta.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: beta.id]?.status = .waitingForInput
		}
		#expect(posted.value.isEmpty)

		await store.send(.view(.terminalSessionStatusChanged(sessionId: betaBehind.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: betaBehind.id]?.status = .waitingForInput
		}
		#expect(posted.value.map(\.sessionId) == [betaBehind.id])
	}

	@Test("withdraws the notification once the session is back at work")
	func removesWhenActiveAgain() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .waitingForInput
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [session]
		let removed = LockIsolated<[UUID]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].remove = { id in removed.withValue { $0.append(id) } }
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .active))) {
			$0.terminals.sessions[id: session.id]?.status = .active
		}
		#expect(removed.value == [session.id])
	}

	@Test("clicking the notification opens the panel on that session")
	func tapOpensSession() async {
		let first = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let second = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [first, second]
		let activated = LockIsolated(false)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].activateApp = { activated.setValue(true) }
		}

		await store.send(.terminalNotificationTapped(sessionId: second.id)) {
			$0.terminals = TerminalTabs(
				sessions: [first, second],
				panes: [TerminalPane(shown: second.id, tabs: [first.id, second.id])],
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": second.id],
				recentSessionIds: [second.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
		await store.finish()
		#expect(activated.value)
	}

	@Test("clicking the notification of a tab in a hidden panel shows the panel as it was, on that tab")
	func tapShowsHiddenPanel() async {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var state = RepositoryListReducer.State()
		// A split left behind when the panel was hidden, the keyboard in alpha's pane.
		state.terminals = TerminalTabs(
			sessions: [alpha, beta],
			panes: [
				TerminalPane(shown: alpha.id, tabs: [alpha.id]),
				TerminalPane(shown: beta.id, tabs: [beta.id]),
			],
			lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": beta.id],
			recentSessionIds: [beta.id, alpha.id]
		)
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].activateApp = {}
		}

		await store.send(.terminalNotificationTapped(sessionId: beta.id)) {
			$0.terminals = TerminalTabs(
				sessions: [alpha, beta],
				panes: [
					TerminalPane(shown: alpha.id, tabs: [alpha.id]),
					TerminalPane(shown: beta.id, tabs: [beta.id]),
				],
				activePaneIndex: 1,
				isPanelVisible: true,
				lastActiveSessionByRepo: ["/repos/alpha": alpha.id, "/repos/beta": beta.id],
				recentSessionIds: [alpha.id, beta.id]
			)
			$0.terminalLayout = TerminalLayoutReducer.State()
		}
	}

	@Test("posts nothing when terminal notifications are turned off")
	func skipsWhenSettingOff() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.status = .active
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [session]
		state.$terminalNotifications.withLock { $0 = false }
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .waitingForInput))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
		}
		let notification = TerminalNotification(title: nil, body: "build finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification)))
	}

	@Test("a status change that neither starts nor stops waiting posts and withdraws nothing")
	func ignoresTransitionsOutsideWaiting() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminals.sessions = [session]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .active))) {
			$0.terminals.sessions[id: session.id]?.status = .active
		}
		await store.send(.view(.terminalSessionStatusChanged(sessionId: session.id, status: .failed("exited")))) {
			$0.terminals.sessions[id: session.id]?.status = .failed("exited")
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
		state.terminals.sessions = [first, second]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: "Claude Code", body: "Claude needs your permission to use Bash")
		await store.send(.view(.terminalNotificationReceived(sessionId: second.id, notification: notification))) {
			$0.terminals.sessions[id: second.id]?.status = .waitingForInput
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
		state.terminals.sessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: nil, body: "build finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification))) {
			$0.terminals.sessions[id: session.id]?.status = .waitingForInput
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
