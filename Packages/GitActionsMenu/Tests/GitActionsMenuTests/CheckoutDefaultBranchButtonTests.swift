import AppUI
import ComposableArchitecture
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

	@Test("Changing the group default branch keeps the checkout button in sync")
	func setDefaultBranchSyncsButton() {
		var state = GitActionsMenuReducer.State(repositoryPath: "/tmp/repo", currentBranch: "feature")
		state.setDefaultBranch("develop")
		#expect(state.checkoutDefaultBranchButton.defaultBranch == "develop")
		#expect(state.mergeMasterButton.defaultBranch == "develop")
	}
}
