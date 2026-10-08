import ComposableArchitecture
import Foundation
import GitCore
import GitGraphFeature
import StagingFeature
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The layout reducer on its own, without the list that handles most of its actions: the
// per-repository tab memory, the sheets it presents, and the in-flight flags behind the
// toolbar's Push and Finish Merge buttons.
@Suite("Terminal layout reducer")
@MainActor
struct TerminalLayoutReducerTests {
	// MARK: - Tab memory

	@Test("activating a tab shows it and remembers it for its repository only")
	func activateRemembersPerRepository() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var layout = TerminalLayoutReducer.State()

		layout.activate(alpha)
		layout.activate(beta)

		#expect(layout.activeRepositoryPath == "/repos/beta")
		#expect(layout.activeSessionId == beta.id)
		#expect(layout.lastActiveSessionByRepo == ["/repos/alpha": alpha.id, "/repos/beta": beta.id])
	}

	@Test("forgetting a tab the repository was not left on keeps the one it was")
	func forgetOnlyDropsTheRememberedTab() {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		var layout = TerminalLayoutReducer.State()
		layout.activate(alphaTwo)

		// Closing a background tab must not cost the repository the tab the user is on.
		layout.forget(sessionId: alphaOne.id, repositoryPath: "/repos/alpha")
		#expect(layout.lastActiveSessionByRepo["/repos/alpha"] == alphaTwo.id)

		layout.forget(sessionId: alphaTwo.id, repositoryPath: "/repos/alpha")
		#expect(layout.lastActiveSessionByRepo["/repos/alpha"] == nil)
	}

	@Test("forgetting a tab under another repository's path leaves both memories alone")
	func forgetIsScopedToRepository() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha")
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var layout = TerminalLayoutReducer.State()
		layout.activate(alpha)
		layout.activate(beta)

		layout.forget(sessionId: alpha.id, repositoryPath: "/repos/beta")

		#expect(layout.lastActiveSessionByRepo == ["/repos/alpha": alpha.id, "/repos/beta": beta.id])
	}

	// MARK: - Sheets

	@Test("the staging button opens the sheet on the repository and its iOS subfolder")
	func stagingButtonPresentsDetail() async {
		let store = TestStore(initialState: TerminalLayoutReducer.State()) {
			TerminalLayoutReducer()
		}

		await store.send(.stagingButtonTapped(repositoryPath: "/repos/alpha", iosSubfolderPath: "ios")) {
			$0.stagingDetail = RepositoryDetail.State(repositoryPath: "/repos/alpha", iosSubfolderPath: "ios")
		}
		await store.send(.stagingDetail(.dismiss)) {
			$0.stagingDetail = nil
		}
	}

	@Test("the git graph button opens the graph, and closing it does nothing else")
	func gitGraphButtonPresentsGraph() async {
		let store = TestStore(initialState: TerminalLayoutReducer.State()) {
			TerminalLayoutReducer()
		}

		await store.send(.gitGraphButtonTapped(repositoryPath: "/repos/alpha", repositoryName: "alpha")) {
			$0.gitGraph = GitGraphReducer.State(repositoryPath: "/repos/alpha", repositoryName: "alpha")
		}
		await store.send(.gitGraph(.dismiss)) {
			$0.gitGraph = nil
		}
	}

	// MARK: - In-flight flags

	@Test("a push completion stops the spinner whether it succeeded or failed", arguments: [true, false])
	func pushCompletionClearsFlag(failed: Bool) async {
		var layout = TerminalLayoutReducer.State()
		layout.isPushing = true
		let store = TestStore(initialState: layout) {
			TerminalLayoutReducer()
		}

		await store.send(.pushCompleted(result: nil, error: failed ? .pushFailed("rejected") : nil)) {
			$0.isPushing = false
		}
	}

	@Test("a finish-merge completion stops the spinner whether it succeeded or failed", arguments: [true, false])
	func finishMergeCompletionClearsFlag(failed: Bool) async {
		var layout = TerminalLayoutReducer.State()
		layout.isFinishingMerge = true
		let store = TestStore(initialState: layout) {
			TerminalLayoutReducer()
		}

		await store.send(.finishMergeCompleted(
			repositoryPath: "/repos/alpha",
			error: failed ? .mergeFailed("conflict") : nil
		)) {
			$0.isFinishingMerge = false
		}
	}
}
