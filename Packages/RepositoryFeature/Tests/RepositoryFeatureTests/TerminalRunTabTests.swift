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
	/// What `TerminalPanesClient.kill` was called with, one entry per call.
	private let killed = LockIsolated<[Set<UUID>]>([])

	@Test("the first run opens a run tab after the repository's tabs, leaving the tab on screen")
	func firstRunAppendsTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta", tabIndex: 5)
		// `kill` is left unimplemented: a first run replaces nothing, so no shell is hung up.
		let store = TestStore(initialState: state(sessions: [alphaOne, alphaTwo, beta], active: alphaOne)) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
		}
		store.exhaustivity = .off

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "/bin/bash run.sh", title: "App", repositoryPath: nil)))))
		await store.finish()

		let sessions = store.state.terminals.sessions
		#expect(sessions.count == 4)
		let run = sessions[3]
		#expect(run.repositoryPath == "/repos/alpha")
		#expect(run.runTitle == "App")
		#expect(run.startupCommand == "/bin/bash run.sh")
		#expect(run.tabIndex == 3)
		#expect(store.state.terminals.activeSessionId == alphaOne.id)
		// At the end of the bar of the pane showing its repository.
		#expect(store.state.terminals.panes.map(\.tabs) == [[alphaOne.id, alphaTwo.id, run.id]])
	}

	@Test("running again replaces the run tab in its place")
	func runAgainReplacesTab() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let oldRun = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "old", runTitle: "App", tabIndex: 2)
		let alphaThree = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 3)
		let store = makeClosingStore(state(sessions: [alphaOne, oldRun, alphaThree], active: alphaOne))

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "new", title: "Widgets", repositoryPath: nil)))))
		await store.finish()

		let sessions = store.state.terminals.sessions
		#expect(sessions[id: oldRun.id] == nil)
		#expect(sessions.map(\.tabIndex) == [1, 2, 3])
		let run = sessions[1]
		#expect(run.runTitle == "Widgets")
		#expect(run.startupCommand == "new")
		#expect(store.state.terminals.activeSessionId == alphaOne.id)
		#expect(store.state.terminals.recentSessionIds.contains(oldRun.id) == false)
		#expect(store.state.terminals.panes.map(\.tabs) == [[alphaOne.id, run.id, alphaThree.id]])
		// What ran there is hung up, and only that.
		#expect(killed.value == [[oldRun.id]])
	}

	@Test("running again from the run tab shows its replacement")
	func runAgainFromRunTabShowsReplacement() async {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let oldRun = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "old", runTitle: "App", tabIndex: 2)
		let store = makeClosingStore(state(sessions: [alphaOne, oldRun], active: oldRun))

		await store.send(.terminalLayout(.simulatorPane(.delegate(.runRequested(command: "new", title: "App", repositoryPath: nil)))))
		await store.finish()

		let run = store.state.terminals.sessions[1]
		#expect(run.id != oldRun.id)
		#expect(store.state.terminals.activeSessionId == run.id)
		#expect(store.state.terminals.isOnScreen(run.id))
		#expect(store.state.terminals.recentSessionIds.contains(oldRun.id) == false)
		#expect(killed.value == [[oldRun.id]])
	}

	@Test("retrying a run tab runs its own command again, not the group's")
	func retryKeepsRunCommand() async {
		var run = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "run it", runTitle: "App", tabIndex: 1)
		run.status = .failed("Terminal process exited (code 1)")
		let store = makeClosingStore(state(sessions: [run], active: run))

		await store.send(.terminals(.retryTab(sessionId: run.id)))
		await store.receive(\.terminals.delegate.sessionRequested)
		await store.receive(\.terminals.sessionBuilt)
		await store.finish()

		let retried = store.state.terminals.sessions[0]
		#expect(retried.id != run.id)
		#expect(retried.runTitle == "App")
		#expect(retried.startupCommand == "run it")
		#expect(killed.value == [[run.id]])
	}

	@Test("run tabs are not saved for the next launch")
	func runTabsAreNotSaved() {
		let shell = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let run = TerminalSession(repositoryPath: "/repos/alpha", startupCommand: "run it", runTitle: "App", tabIndex: 2)

		let saved = SavedTerminalTabs(TerminalTabs(sessions: [shell, run]), panes: [:])

		#expect(saved.tabs.map(\.tabIndex) == [1])
	}

	/// The panel open on `active`, its repository's tabs in the one pane.
	private func state(sessions: [TerminalSession], active: TerminalSession) -> RepositoryListReducer.State {
		var state = RepositoryListReducer.State()
		var terminals = TerminalTabs(sessions: IdentifiedArray(uniqueElements: sessions))
		terminals.show(active)
		terminals.showPanel()
		state.terminals = terminals
		state.terminalLayout = TerminalLayoutReducer.State()
		return state
	}

	/// A non-exhaustive store whose closed sessions are recorded in `killed`.
	private func makeClosingStore(_ state: RepositoryListReducer.State) -> TestStoreOf<RepositoryListReducer> {
		let store = TestStore(initialState: state) {
			RepositoryListReducer()
		} withDependencies: {
			$0.uuid = .incrementing
			$0[TerminalPanesClient.self].kill = { [killed] ids in
				killed.withValue { $0.append(Set(ids)) }
			}
		}
		store.exhaustivity = .off
		return store
	}
}
