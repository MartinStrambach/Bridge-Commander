import AppUI
import ComposableArchitecture
import GitCore
import Testing
@testable import GitActionsMenu

@MainActor
struct StashButtonTests {
	private static let entry = GitStashEntry(
		reference: "stash@{1}",
		branch: "feature",
		message: "abc1234 Work in progress"
	)

	@Test("finding a stash makes the apply items available")
	func findingAStashShowsTheApplyItems() async {
		let store = TestStore(
			initialState: StashButtonReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			StashButtonReducer()
		}

		#expect(store.state.hasStash == false)

		await store.send(.didFindStash(Self.entry)) {
			$0.stash = Self.entry
		}
		#expect(store.state.hasStash)
	}

	@Test("an empty stash list hides the apply items again")
	func emptyResultClearsTheStash() async {
		let store = TestStore(
			initialState: StashButtonReducer.State(
				repositoryPath: "/tmp/repo",
				currentBranch: "feature",
				stash: Self.entry
			)
		) {
			StashButtonReducer()
		}

		await store.send(.didFindStash(nil)) {
			$0.stash = nil
		}
		#expect(store.state.hasStash == false)
	}

	@Test("apply, pop and clear do nothing when no stash was detected")
	func tapsAreIgnoredWithoutAStash() async {
		let store = TestStore(
			initialState: StashButtonReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			StashButtonReducer()
		}

		await store.send(.stashApplyTapped)
		await store.send(.stashPopTapped)
		await store.send(.stashClearTapped)
		#expect(store.state.isProcessing == false)
		#expect(store.state.confirmationDialog == nil)
	}

	@Test("clearing asks before deleting, naming the entry in the prompt")
	func clearConfirmsFirst() async {
		let store = TestStore(
			initialState: StashButtonReducer.State(
				repositoryPath: "/tmp/repo",
				currentBranch: "feature",
				stash: Self.entry
			)
		) {
			StashButtonReducer()
		}

		// Tapping only opens the dialog — nothing runs until it is confirmed.
		await store.send(.stashClearTapped) {
			$0.confirmationDialog = StashButtonReducer.clearConfirmation(for: Self.entry)
		}
		#expect(store.state.isProcessing == false)

		await store.send(.confirmationDialog(.dismiss)) {
			$0.confirmationDialog = nil
		}
		#expect(store.state.isProcessing == false)
	}

	@Test("each completion clears the running operation")
	func completionsClearTheOperation() async {
		let completions: [(StashButtonReducer.Operation, StashButtonReducer.Action)] = [
			(.stashing, .stashCompleted(success: true, error: nil)),
			(.applying, .stashApplyCompleted(success: true, error: nil)),
			(.popping, .stashPopCompleted(success: false, error: "boom")),
			(.clearing, .stashClearCompleted(success: true, error: nil)),
		]

		for (operation, completion) in completions {
			let store = TestStore(
				initialState: StashButtonReducer.State(
					repositoryPath: "/tmp/repo",
					currentBranch: "feature",
					stash: Self.entry,
					operation: operation
				)
			) {
				StashButtonReducer()
			}

			await store.send(completion) {
				$0.operation = nil
			}
		}
	}

	@Test("the progress label distinguishes stashing from restoring")
	func progressLabels() {
		#expect(StashButtonReducer.Operation.stashing.progressText == "Stashing...")
		#expect(StashButtonReducer.Operation.applying.progressText == "Applying stash...")
		#expect(StashButtonReducer.Operation.popping.progressText == "Popping stash...")
		#expect(StashButtonReducer.Operation.clearing.progressText == "Clearing stash...")
		#expect(
			StashButtonReducer.Operation.popping.progressHelpText
				== "Restoring stashed changes and dropping the stash..."
		)
	}
}

@MainActor
struct GitActionsMenuStashWiringTests {
	@Test("the stash button follows the branch the row reports")
	func stashButtonFollowsTheBranch() {
		// The row seeds the menu before its status fetch lands, so the branch arrives late.
		// Leaving the stash button's copy behind is what kept the apply items hidden.
		var state = GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "alpha")
		#expect(state.stashButton.currentBranch == "alpha")

		state.setCurrentBranch("feature/login")

		#expect(state.currentBranch == "feature/login")
		#expect(state.stashButton.currentBranch == "feature/login")
	}

	@Test("a successful apply keeps the stash and re-checks the list")
	func applySuccessAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off

		await store.send(.stashButton(.stashApplyCompleted(success: true, error: nil)))

		#expect(store.state.alert == ScrollableAlertReducer.State(
			title: "Stash Applied",
			message: "Stashed changes have been restored. The stash is still available.",
			isError: false
		))
		await store.receive(\.stashButton.checkStashStatus)
	}

	@Test("a failed apply reports the git error")
	func applyErrorAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off

		await store.send(.stashButton(.stashApplyCompleted(success: false, error: "conflict")))

		#expect(store.state.alert == ScrollableAlertReducer.State(
			title: "Apply Stash Failed",
			message: "conflict",
			isError: true
		))
	}

	@Test("a successful pop reports that the stash was removed")
	func popSuccessAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off

		await store.send(.stashButton(.stashPopCompleted(success: true, error: nil)))

		#expect(store.state.alert == ScrollableAlertReducer.State(
			title: "Stash Popped",
			message: "Stashed changes have been restored and the stash was removed.",
			isError: false
		))
		await store.receive(\.stashButton.checkStashStatus)
	}

	@Test("a successful clear reports that nothing was restored")
	func clearSuccessAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off

		await store.send(.stashButton(.stashClearCompleted(success: true, error: nil)))

		#expect(store.state.alert == ScrollableAlertReducer.State(
			title: "Stash Cleared",
			message: "The stash has been deleted without being restored.",
			isError: false
		))
		await store.receive(\.stashButton.checkStashStatus)
	}

	@Test("a failed clear reports the git error")
	func clearErrorAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off

		await store.send(.stashButton(.stashClearCompleted(success: false, error: "no such stash")))

		#expect(store.state.alert == ScrollableAlertReducer.State(
			title: "Clear Stash Failed",
			message: "no such stash",
			isError: true
		))
	}
}
