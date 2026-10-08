import ComposableArchitecture
import Foundation
import SimulatorFeature
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The simulator pane's Run button, as `RepositoryListReducer` turns it into a terminal tab.
@Suite("Terminal run tab")
@MainActor
struct TerminalRunTabTests {
	@Test("the first run opens a run tab after the repository's tabs and shows it")
	func firstRunAppendsTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 5)
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo, beta], active: alphaOne)) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "/bin/bash run.sh", title: "App")))))

		let sessions = store.state.terminalSessions
		#expect(sessions.count == 4)
		let run = sessions[3]
		#expect(run.repositoryPath == "/repos/alpha")
		#expect(run.runTitle == "App")
		#expect(run.startupCommand == "/bin/bash run.sh")
		#expect(run.tabIndex == 3)
		#expect(store.state.terminalLayout?.activeSessionId == run.id)
	}

	@Test("running again replaces the run tab in its place")
	func runAgainReplacesTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let oldRun = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "old", runTitle: "App", tabIndex: 2)
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = TestStore(initialState: state(sessions: [alphaOne, oldRun, alphaThree], active: alphaOne)) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "new", title: "Widgets")))))

		let sessions = store.state.terminalSessions
		#expect(sessions[id: oldRun.id] == nil)
		#expect(sessions.map(\.tabIndex) == [1, 2, 3])
		let run = sessions[1]
		#expect(run.runTitle == "Widgets")
		#expect(run.startupCommand == "new")
		#expect(store.state.terminalLayout?.activeSessionId == run.id)
		#expect(store.state.terminalLayout?.recentSessionIds.contains(oldRun.id) == false)
	}

	@Test("retrying a run tab runs its own command again, not the group's")
	func retryKeepsRunCommand() async {
		var run = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "run it", runTitle: "App", tabIndex: 1)
		run.status = .failed("Terminal process exited (code 1)")
		let store = TestStore(initialState: state(sessions: [run], active: run)) {
			RepositoryListReducer()
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.retryTab(sessionId: run.id)))

		let retried = store.state.terminalSessions[0]
		#expect(retried.id != run.id)
		#expect(retried.runTitle == "App")
		#expect(retried.startupCommand == "run it")
	}

	@Test("run tabs are not saved for the next launch")
	func runTabsAreNotSaved() {
		let shell = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let run = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "run it", runTitle: "App", tabIndex: 2)

		let saved = SavedTerminalTabs(sessions: [shell, run], layout: nil, panes: [:])

		#expect(saved.tabs.map(\.tabIndex) == [1])
	}

	private func state(sessions: [TerminalSession], active: TerminalSession) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		state.terminalSessions = IdentifiedArray(uniqueElements: sessions)
		var layout = TerminalLayoutReducer.State()
		layout.activate(active)
		state.terminalLayout = layout
		return state
	}
}
