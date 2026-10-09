import ComposableArchitecture
import Foundation
import TerminalFeature
import Testing
import ToolsIntegration
@testable import RepositoryFeature

// A tab is named by the title its program sets (OSC 0/2) — Claude Code's summary of the
// conversation — instead of "Terminal N".
@Suite("Terminal tab titles")
@MainActor
struct TerminalTabTitleTests {
	@Test("a title the program sets names the tab, and an empty one gives the number back")
	func titleChangesAreKept() async {
		let session = TerminalSession(repositoryPath: "/repos/alpha")
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionTitleChanged(sessionId: session.id, title: "Fix the login bug"))) {
			$0.terminalSessions[id: session.id]?.title = "Fix the login bug"
		}
		await store.send(.view(.terminalSessionTitleChanged(sessionId: session.id, title: nil))) {
			$0.terminalSessions[id: session.id]?.title = nil
		}
	}

	@Test("a title arriving from a session that is gone changes nothing")
	func lateTitleIsIgnored() async {
		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		}

		await store.send(.view(.terminalSessionTitleChanged(sessionId: UUID(), title: "Late")))
	}

	@Test("a notification names a titled tab by its title, even as the repository's only tab")
	func notificationNamesTheTab() async {
		var session = TerminalSession(repositoryPath: "/repos/alpha")
		session.title = "Fix the login bug"
		var state = RepositoryListReducer.State()
		state.terminalSessions = [session]
		let posted = LockIsolated<[TerminalNotificationContent]>([])
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalNotificationClient.self].post = { content in posted.withValue { $0.append(content) } }
		}

		let notification = TerminalNotification(title: "Build", body: "Finished")
		await store.send(.view(.terminalNotificationReceived(sessionId: session.id, notification: notification)))
		#expect(posted.value.map(\.subtitle) == ["alpha · Fix the login bug"])
	}

	@Test("the title is saved with the tab and shown again when the tab reopens")
	func titleSurvivesRelaunch() async {
		var titled = TerminalSession(repositoryPath: "/repos/alpha")
		titled.title = "Fix the login bug"
		let untitled = TerminalSession(repositoryPath: "/repos/beta")

		let saved = SavedTerminalTabs(sessions: [titled, untitled], layout: nil, panes: [:])
		#expect(saved.tabs.map(\.title) == ["Fix the login bug", nil])

		let store = TestStore(initialState: RepositoryListReducer.State()) {
			RepositoryListReducer()
		} withDependencies: {
			$0[TerminalTabArchiveClient.self].load = { saved }
		}
		store.exhaustivity = .off
		await store.send(.restoreTerminalTabs)
		#expect(store.state.terminalSessions.map(\.title) == ["Fix the login bug", nil])
	}

	@Test("tabs saved before titles were still load")
	func decodesTabsWithoutTitle() throws {
		let json = Data(
			"""
			{"tabs":[{"repositoryPath":"/repos/alpha","directory":"/repos/alpha","tabIndex":1,\
			"isRepositoryCurrentTab":true,"isOnScreen":false}]}
			""".utf8
		)

		let saved = try JSONDecoder().decode(SavedTerminalTabs.self, from: json)
		#expect(saved.tabs.map(\.title) == [nil])
	}
}
