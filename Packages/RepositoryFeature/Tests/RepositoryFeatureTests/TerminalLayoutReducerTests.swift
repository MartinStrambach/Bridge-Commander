import ComposableArchitecture
import Foundation
import GitCore
import GitGraphFeature
import StagingFeature
import TerminalFeature
import Testing
@testable import RepositoryFeature

// The layout reducer on its own, without the list that handles most of its actions: the sheets
// it presents and the in-flight flags behind the toolbar's Push and Finish Merge buttons. The
// tabs and panes are `TerminalTabs`'s.
@Suite("Terminal layout reducer")
@MainActor
struct TerminalLayoutReducerTests {
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

// The per-repository tab memory the layout state used to hold is `TerminalTabs`'s now.
@Suite("Terminal tab memory")
struct TerminalTabMemoryTests {
	@Test("showing a tab gives it the keyboard and remembers it for its repository only")
	func showRemembersPerRepository() {
		let alpha = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var tabs = TerminalTabs(sessions: [alpha, beta])

		tabs.show(alpha)
		tabs.show(beta)

		#expect(tabs.activeRepositoryPath == "/repos/beta")
		#expect(tabs.activeSessionId == beta.id)
		#expect(tabs.lastActiveSessionByRepo == ["/repos/alpha": alpha.id, "/repos/beta": beta.id])
		#expect(tabs.recentSessionIds == [alpha.id, beta.id])
	}

	@Test("closing a tab the repository was not left on keeps the one it was")
	func closingBackgroundTabKeepsTheRememberedTab() {
		let alphaOne = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 1)
		let alphaTwo = TerminalSession(repositoryPath: "/repos/alpha", tabIndex: 2)
		let beta = TerminalSession(repositoryPath: "/repos/beta")
		var tabs = TerminalTabs(sessions: [alphaOne, alphaTwo, beta])
		tabs.show(alphaTwo)
		tabs.show(beta)

		// Closing a background tab must not cost the repository the tab the user was on.
		tabs.close([alphaOne.id])
		#expect(tabs.lastActiveSessionByRepo == ["/repos/alpha": alphaTwo.id, "/repos/beta": beta.id])

		// Closing the remembered one, off screen, leaves the repository with no tab to go back to.
		tabs.close([alphaTwo.id])
		#expect(tabs.lastActiveSessionByRepo == ["/repos/beta": beta.id])
	}
}
