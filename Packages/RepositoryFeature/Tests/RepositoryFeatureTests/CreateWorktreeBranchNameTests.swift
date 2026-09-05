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

	@Test("other bound fields are untouched by the sanitizer")
	func otherBindingsAreNotSanitized() async {
		let store = makeStore()

		await store.send(\.binding.branchSearchText, "release 2") {
			$0.branchSearchText = "release 2"
		}
	}
}
