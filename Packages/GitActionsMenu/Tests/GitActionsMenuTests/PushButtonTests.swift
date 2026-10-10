import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import GitActionsMenu

// A push from the menu alerts its outcome either way; the terminal toolbar's Push button pushes
// quietly, alerting only a failure.
@MainActor
struct PushButtonTests {
	@Test("a push from the menu alerts its success")
	func menuPushAlertsSuccess() async {
		let store = makeStore(push: { _ in GitPushHelper.PushResult(isUpToDate: false, message: "") })

		await store.send(.pushButton(.pushTapped)) {
			$0.pushButton.isPushing = true
		}
		await store.receive(\.pushButton.pushCompleted) {
			$0.pushButton.isPushing = false
			$0.alert = ScrollableAlertReducer.State(
				title: "Push Successful",
				message: "Successfully pushed commits to remote branch.",
				isError: false
			)
		}
	}

	@Test("a quiet push does not alert its success")
	func quietPushIsSilentOnSuccess() async {
		let store = makeStore(push: { _ in GitPushHelper.PushResult(isUpToDate: false, message: "") })

		await store.send(.pushButton(.quietPushTapped)) {
			$0.pushButton.isPushing = true
		}
		await store.receive(\.pushButton.pushCompleted) {
			$0.pushButton.isPushing = false
		}
		#expect(store.state.alert == nil)
	}

	@Test("a quiet push still alerts a failure")
	func quietPushAlertsFailure() async {
		let error = GitError.pushFailed("rejected: non-fast-forward")
		let store = makeStore(push: { _ in throw error })

		await store.send(.pushButton(.quietPushTapped)) {
			$0.pushButton.isPushing = true
		}
		await store.receive(\.pushButton.pushCompleted) {
			$0.pushButton.isPushing = false
			$0.alert = ScrollableAlertReducer.State(
				title: "Push Failed",
				message: error.localizedDescription,
				isError: true
			)
		}
	}

	@Test("a quiet push leaves the next push from the menu alerting its success")
	func quietPushDoesNotLinger() async {
		let store = makeStore(push: { _ in GitPushHelper.PushResult(isUpToDate: true, message: "") })

		await store.send(.pushButton(.quietPushTapped))
		await store.receive(\.pushButton.pushCompleted)
		await store.send(.pushButton(.pushTapped))
		await store.receive(\.pushButton.pushCompleted) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Push Successful",
				message: "Everything is already up to date with the remote branch.",
				isError: false
			)
		}
	}

	private func makeStore(
		push: @escaping @Sendable (String) async throws -> GitPushHelper.PushResult
	) -> TestStoreOf<GitActionsMenuReducer> {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		} withDependencies: {
			$0[GitClient.self].push = push
		}
		// Each completion also re-checks the stash, which is not under test here.
		store.exhaustivity = .off(showSkippedAssertions: false)
		return store
	}
}
