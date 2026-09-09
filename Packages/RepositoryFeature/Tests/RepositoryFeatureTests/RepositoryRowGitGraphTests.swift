import ComposableArchitecture
import GitGraphFeature
import Testing
@testable import RepositoryFeature

@Suite("Repository row opens the commit graph from its type icon")
struct RepositoryRowGitGraphTests {
	@Test("tapping the icon presents the graph for this row's repository")
	@MainActor
	func iconTapPresentsGraph() async {
		let store = TestStore(
			initialState: RepositoryRowReducer.State(
				path: "/repos/app",
				name: "app",
				branchName: "main"
			)
		) {
			RepositoryRowReducer()
		}

		await store.send(.repositoryIconTapped) {
			$0.gitGraph = GitGraphReducer.State(repositoryPath: "/repos/app", repositoryName: "app")
		}
	}

	@Test("a worktree row opens the graph on the worktree's own path, not the parent repo's")
	@MainActor
	func worktreeRowUsesItsOwnPath() async {
		let store = TestStore(
			initialState: RepositoryRowReducer.State(
				path: "/repos/worktrees/app/MOB-1_feature",
				name: "app",
				branchName: "MOB-1_feature",
				isWorktree: true
			)
		) {
			RepositoryRowReducer()
		}

		await store.send(.repositoryIconTapped) {
			$0.gitGraph = GitGraphReducer.State(
				repositoryPath: "/repos/worktrees/app/MOB-1_feature",
				repositoryName: "app"
			)
		}
	}

	/// Unlike the staging sheet, the graph only reads (`git log` / `git show`), so closing it
	/// cannot have changed the row's counts. An unexpected `.refresh` here fails the test.
	@Test("closing the graph does not refresh the row")
	@MainActor
	func dismissDoesNotRefresh() async {
		let store = TestStore(
			initialState: RepositoryRowReducer.State(
				path: "/repos/app",
				name: "app",
				branchName: "main"
			)
		) {
			RepositoryRowReducer()
		}

		await store.send(.repositoryIconTapped) {
			$0.gitGraph = GitGraphReducer.State(repositoryPath: "/repos/app", repositoryName: "app")
		}
		await store.send(.gitGraph(.dismiss)) {
			$0.gitGraph = nil
		}
		await store.finish()
	}
}
