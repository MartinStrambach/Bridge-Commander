import ComposableArchitecture
import Testing
@testable import RepositoryFeature

@Suite("Create worktree dialog: new branch name input")
@MainActor
struct CreateWorktreeBranchNameTests {
	private func makeStore() -> TestStoreOf<CreateWorktreeButtonReducer> {
		TestStore(initialState: CreateWorktreeButtonReducer.State(repositoryPath: "/repos/app")) {
			CreateWorktreeButtonReducer()
		}
	}

	@Test("spaces typed into the branch name field are replaced with underscores as you type")
	func typedSpacesBecomeUnderscores() async {
		let store = makeStore()

		await store.send(\.binding.branchName, "fix login bug") {
			$0.branchName = "fix_login_bug"
		}
	}

	@Test("a name without spaces is stored verbatim")
	func nameWithoutSpacesIsUnchanged() async {
		let store = makeStore()

		await store.send(\.binding.branchName, "feature/MOB-123_login") {
			$0.branchName = "feature/MOB-123_login"
		}
	}

	@Test("leading spaces are dropped instead of becoming underscores")
	func leadingSpacesAreDropped() async {
		let store = makeStore()

		await store.send(\.binding.branchName, "  fix login") {
			$0.branchName = "fix_login"
		}
	}

	@Test("a name of only spaces stays empty and cannot be submitted")
	func onlySpacesCannotBeSubmitted() async {
		let store = makeStore()

		await store.send(\.binding.branchName, "   ")
		// Exhaustive: no state change (`isCreating` stays false) and no git process. Before, the
		// spaces became "___", which passed the empty-name guard and was created as a branch.
		await store.send(.confirmCreation)
	}

		@Test("other bound fields are untouched by the sanitizer")
	func otherBindingsAreNotSanitized() async {
		let store = makeStore()

		await store.send(\.binding.branchSearchText, "release 2") {
			$0.branchSearchText = "release 2"
		}
	}
}
