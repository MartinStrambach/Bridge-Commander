import AppUI
import ComposableArchitecture
import Testing
@testable import GitActionsMenu

@MainActor
struct GitActionsMenuEntriesTests {
	private func titles(_ configure: (inout GitActionsMenuReducer.State) -> Void) -> [String] {
		var state = GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		configure(&state)
		let store = Store(initialState: state) { GitActionsMenuReducer() }
		return store.menuEntries.map { entry in
			if case let .action(action) = entry {
				action.title
			}
			else {
				"?"
			}
		}
	}

	@Test("a tracked feature branch offers fetch, pull, and merging or checking out the default branch")
	func trackedFeatureBranch() {
		#expect(titles { $0.hasRemoteBranch = true } == [
			"Fetch", "Pull", "Merge default branch", "Checkout default branch",
		])
	}

	@Test("an untracked branch can only be pushed; local commits add push to a tracked one")
	func pushAppearsWhenThereIsSomethingToPush() {
		#expect(titles { _ in }.first == "Push")
		#expect(titles {
			$0.hasRemoteBranch = true
			$0.unpushedCommitsCount = 2
		}.prefix(3) == ["Fetch", "Pull", "Push"])
	}

	@Test("during a merge only aborting it and the remote actions are offered")
	func mergeInProgress() {
		#expect(titles {
			$0.hasRemoteBranch = true
			$0.isMergeInProgress = true
			$0.stashButton.hasChanges = true
		} == ["Abort Merge", "Fetch", "Pull"])
	}

	@Test("changes offer stashing and discarding")
	func changes() {
		#expect(titles {
			$0.hasRemoteBranch = true
			$0.stashButton.hasChanges = true
			$0.discardButton.hasTrackedChanges = true
			$0.discardButton.hasUntrackedFiles = true
		} == [
			"Fetch", "Pull", "Stash", "Discard Tracked Changes", "Discard All Changes",
			"Merge default branch", "Checkout default branch",
		])
	}

	@Test("the default branch is not offered to merge into or check out")
	func onDefaultBranch() {
		var state = GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "main")
		state.hasRemoteBranch = true
		let store = Store(initialState: state) { GitActionsMenuReducer() }
		#expect(store.menuEntries.count == 2)
	}
}
