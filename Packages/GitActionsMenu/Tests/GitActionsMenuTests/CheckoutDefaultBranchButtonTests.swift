import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Testing
@testable import GitActionsMenu

@MainActor
struct CheckoutDefaultBranchButtonTests {
	@Test("Tapping checkout calls the client with the configured default branch and reports the result")
	func tapCheckout() async {
		let store = TestStore(
			initialState: CheckoutDefaultBranchButtonReducer.State(repositoryPath: "/tmp/repo", defaultBranch: "develop")
		) {
			CheckoutDefaultBranchButtonReducer()
		} withDependencies: {
			$0[GitClient.self].checkoutDefaultBranch = { path, baseBranch in
				#expect(path == "/tmp/repo")
				#expect(baseBranch == "develop")
				return "develop"
			}
		}

		await store.send(.checkoutTapped) {
			$0.isCheckingOut = true
		}
		await store.receive(\.checkoutCompleted) {
			$0.isCheckingOut = false
		}
	}

	@Test("A GitError from the client is forwarded as a failure")
	func gitErrorForwarded() async {
		let store = TestStore(
			initialState: CheckoutDefaultBranchButtonReducer.State(repositoryPath: "/tmp/repo")
		) {
			CheckoutDefaultBranchButtonReducer()
		} withDependencies: {
			$0[GitClient.self].checkoutDefaultBranch = { _, _ in
				throw GitError.checkoutFailed("dirty tree")
			}
		}

		await store.send(.checkoutTapped) {
			$0.isCheckingOut = true
		}
		await store.receive(.checkoutCompleted(result: .failure(.checkoutFailed("dirty tree")))) {
			$0.isCheckingOut = false
		}
	}

	@Test("Checkout & Pull pulls the branch it switched to")
	func checkoutAndPull() async {
		let store = TestStore(
			initialState: CheckoutDefaultBranchButtonReducer.State(repositoryPath: "/tmp/repo", defaultBranch: "develop")
		) {
			CheckoutDefaultBranchButtonReducer()
		} withDependencies: {
			$0[GitClient.self].checkoutDefaultBranch = { _, _ in "develop" }
			$0[GitClient.self].pull = { path in
				#expect(path == "/tmp/repo")
				return GitPullHelper.PullResult(commitCount: 3, isAlreadyUpToDate: false)
			}
		}

		await store.send(.checkoutAndPullTapped) {
			$0.isCheckingOut = true
			$0.isPullingAfterCheckout = true
		}
		await store.receive(.checkoutAndPullCompleted(result: .success(.init(
			branch: "develop",
			pull: .success(GitPullHelper.PullResult(commitCount: 3, isAlreadyUpToDate: false))
		)))) {
			$0.isCheckingOut = false
			$0.isPullingAfterCheckout = false
		}
	}

	@Test("A failed pull after Checkout & Pull still reports the branch that was checked out")
	func checkoutAndPullFailedPull() async {
		let store = TestStore(
			initialState: CheckoutDefaultBranchButtonReducer.State(repositoryPath: "/tmp/repo")
		) {
			CheckoutDefaultBranchButtonReducer()
		} withDependencies: {
			$0[GitClient.self].checkoutDefaultBranch = { _, _ in "main" }
			$0[GitClient.self].pull = { _ in throw GitError.pullFailed("no tracking information") }
		}

		await store.send(.checkoutAndPullTapped) {
			$0.isCheckingOut = true
			$0.isPullingAfterCheckout = true
		}
		await store.receive(.checkoutAndPullCompleted(result: .success(.init(
			branch: "main",
			pull: .failure(.pullFailed("no tracking information"))
		)))) {
			$0.isCheckingOut = false
			$0.isPullingAfterCheckout = false
		}
	}

	@Test("A failed checkout skips the pull")
	func checkoutAndPullFailedCheckout() async {
		let store = TestStore(
			initialState: CheckoutDefaultBranchButtonReducer.State(repositoryPath: "/tmp/repo")
		) {
			CheckoutDefaultBranchButtonReducer()
		} withDependencies: {
			$0[GitClient.self].checkoutDefaultBranch = { _, _ in throw GitError.checkoutFailed("dirty tree") }
			// Unimplemented `pull` fails the test if it is called.
		}

		await store.send(.checkoutAndPullTapped) {
			$0.isCheckingOut = true
			$0.isPullingAfterCheckout = true
		}
		await store.receive(.checkoutAndPullCompleted(result: .failure(.checkoutFailed("dirty tree")))) {
			$0.isCheckingOut = false
			$0.isPullingAfterCheckout = false
		}
	}
}

@MainActor
struct GitActionsMenuCheckoutWiringTests {
	@Test("Successful checkout names the branch that was switched to")
	func successAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.checkoutDefaultBranchButton(.checkoutCompleted(result: .success("main")))) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Checkout Successful",
				message: "Switched to main.",
				isError: false
			)
		}
	}

	@Test("Failed checkout shows the git error")
	func errorAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		let error = GitError.checkoutFailed("Branch 'main' was not found locally or on origin.")
		await store.send(.checkoutDefaultBranchButton(.checkoutCompleted(result: .failure(error)))) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Checkout Failed",
				message: error.localizedDescription,
				isError: true
			)
		}
	}

	@Test("Successful Checkout & Pull names the branch and what was pulled")
	func checkoutAndPullSuccessAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.checkoutDefaultBranchButton(.checkoutAndPullCompleted(result: .success(.init(
			branch: "main",
			pull: .success(GitPullHelper.PullResult(commitCount: 1, isAlreadyUpToDate: false))
		))))) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Checkout & Pull Successful",
				message: "Switched to main. Pulled 1 commit from the remote branch.",
				isError: false
			)
		}
	}

	@Test("A failed pull after checking out says the branch was switched")
	func checkoutAndPullFailedPullAlert() async {
		let store = TestStore(
			initialState: GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		) {
			GitActionsMenuReducer()
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		let error = GitError.pullFailed("no tracking information")
		await store.send(.checkoutDefaultBranchButton(.checkoutAndPullCompleted(result: .success(.init(
			branch: "main",
			pull: .failure(error)
		))))) {
			$0.alert = ScrollableAlertReducer.State(
				title: "Pull Failed",
				message: "Switched to main, but the pull failed:\n\(error.localizedDescription)",
				isError: true
			)
		}
	}

	@Test("Changing the group default branch keeps the checkout button in sync")
	func setDefaultBranchSyncsButton() {
		var state = GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		state.setDefaultBranch("develop")
		#expect(state.checkoutDefaultBranchButton.defaultBranch == "develop")
		#expect(state.mergeMasterButton.defaultBranch == "develop")
	}
}
