import AppUI
import ComposableArchitecture
import Testing
@testable import GitActionsMenu

@MainActor
struct DiscardButtonTests {
	@Test("Tapping discard tracked presents the tracked confirmation dialog")
	func discardTrackedTappedPresentsDialog() async {
		let store = TestStore(
			initialState: DiscardButtonReducer.State(repositoryPath: "/tmp/repo")
		) {
			DiscardButtonReducer()
		}

		await store.send(.discardTrackedTapped) {
			$0.confirmationDialog = DiscardButtonReducer.trackedConfirmation
		}
	}

	@Test("Tapping discard all presents the all confirmation dialog")
	func discardAllTappedPresentsDialog() async {
		let store = TestStore(
			initialState: DiscardButtonReducer.State(repositoryPath: "/tmp/repo")
		) {
			DiscardButtonReducer()
		}

		await store.send(.discardAllTapped) {
			$0.confirmationDialog = DiscardButtonReducer.allConfirmation
		}
	}

	@Test("Completion clears the processing flag")
	func completionClearsProcessing() async {
		var initialState = DiscardButtonReducer.State(repositoryPath: "/tmp/repo")
		initialState.isProcessing = true
		let store = TestStore(initialState: initialState) {
			DiscardButtonReducer()
		}

		await store.send(.discardCompleted(success: true, error: nil)) {
			$0.isProcessing = false
		}
	}
}

@MainActor
struct GitActionsMenuDiscardWiringTests {
	@Test("Successful discard shows a success alert")
	func successAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}

		await store.send(.discardButton(.discardCompleted(success: true, error: nil))) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Changes Discarded",
				message: "Local changes have been discarded successfully.",
				isError: false
			)
		}
	}

	@Test("Failed discard shows an error alert")
	func errorAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}

		await store.send(.discardButton(.discardCompleted(success: false, error: "boom"))) {
			$0.alert = ScrollableAlertReducer.State(title: "Discard Failed", message: "boom", isError: true)
		}
	}
}
