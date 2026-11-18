import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import GitActionsMenu

@MainActor
struct PushButtonTests {
	private nonisolated static let rejection = GitError.pushFailed("""
	To github.com:owner/repo.git
	 ! [rejected]        feature -> feature (non-fast-forward)
	error: failed to push some refs to 'github.com:owner/repo.git'
	""")

	private nonisolated static let feature = GitRejectedPush(localBranch: "feature", remoteBranch: "feature")

	@Test("Push and Force Push ask the client for a plain and a lease push", arguments: [false, true])
	func pushModes(force: Bool) async {
		let action: PushButtonReducer.Action = force ? .forcePushTapped(Self.feature) : .pushTapped
		let expectedMode: GitPushHelper.Mode = force ? .forceWithLease(Self.feature) : .normal
		let result = GitPushHelper.PushResult(isUpToDate: false, message: "")
		let store = TestStore(initialState: PushButtonReducer.State(repositoryPath: "/tmp/repo")) {
			PushButtonReducer()
		} withDependencies: {
			$0[GitClient.self].push = { path, mode in
				#expect(path == "/tmp/repo")
				#expect(mode == expectedMode)
				return result
			}
		}

		await store.send(action) {
			$0.isPushing = true
		}
		await store.receive(.pushCompleted(result: result, error: nil)) {
			$0.isPushing = false
		}
	}

	@Test("A push rejected as non-fast-forward offers Force Push, which pushes with lease")
	func rejectedPushOffersForcePush() async {
		let pushedModes = LockIsolated<[GitPushHelper.Mode]>([])
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/nonexistent/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		} withDependencies: {
			$0[GitClient.self].push = { _, mode in
				pushedModes.withValue { $0.append(mode) }
				if mode == .normal {
					throw Self.rejection
				}
				return GitPushHelper.PushResult(isUpToDate: false, message: "")
			}
		}
		// Every completion re-checks the stash, which is not what this test is about.
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.pushButton(.pushTapped))
		await store.receive(\.pushButton.pushCompleted) {
			$0.alert = GitActionsMenuReducer.pushFailedAlert(for: Self.rejection)
			$0.forcePushOffer = Self.feature
		}
		#expect(store.state.alert?.actionTitle == "Force Push")

		await store.send(.alert(.presented(.actionTapped))) {
			$0.alert = nil
			$0.forcePushOffer = nil
		}
		await store.receive(\.pushButton.forcePushTapped) {
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
		#expect(pushedModes.value == [.normal, .forceWithLease(Self.feature)])
		await store.skipReceivedActions()
	}

	@Test("Other push failures offer no Force Push", arguments: [
		GitError.pushFailed(" ! [rejected]        feature -> feature (fetch first)"),
		GitError.pushFailed("fatal: could not read from remote repository."),
	])
	func otherFailuresOfferNothing(error: GitError) {
		let alert = GitActionsMenuReducer.pushFailedAlert(for: error)
		#expect(alert.actionTitle == nil)
		#expect(alert.message == error.localizedDescription)
	}
}
