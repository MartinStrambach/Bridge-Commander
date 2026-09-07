import ComposableArchitecture
import Foundation
import GitCore
import Testing

@testable import GitGraphFeature

// Selecting a commit in the graph opens its diff in the bottom pane. These tests pin down which
// commit is selected as the user clicks around and as the graph reloads underneath them; the
// diffs themselves come from `GitCommitDiffClient`, stubbed out here.
@Suite("Commit selection")
@MainActor
struct CommitSelectionTests {

	// MARK: - Fixtures

	private static let repositoryPath = "/tmp/repo"

	private func commit(_ hash: String, parents: [String] = []) -> GitLogCommit {
		GitLogCommit(
			hash: hash,
			parents: parents,
			author: "Author",
			date: Date(timeIntervalSince1970: 1_700_000_000),
			refs: [],
			subject: "Subject of \(hash)"
		)
	}

	private func store(
		commits: [GitLogCommit],
		files: [GitCore.FileChange] = []
	) -> TestStoreOf<GitGraphReducer> {
		var state = GitGraphReducer.State(
			repositoryPath: Self.repositoryPath,
			repositoryName: "repo"
		)
		state.rows = GitGraphLayout.layout(commits: commits)

		return TestStore(initialState: state) {
			GitGraphReducer()
		} withDependencies: {
			$0[GitCommitDiffClient.self].fetchFileChanges = { _, _ in files }
			$0[GitCommitDiffClient.self].fetchFileDiff = { _, _, _ in nil }
		}
	}

	/// Drains the child's load of an empty file list, which every selection kicks off.
	private func receiveEmptyDetailLoad(_ store: TestStoreOf<GitGraphReducer>) async {
		await store.receive(\.commitDetail.task) {
			$0.commitDetail?.isLoadingFiles = true
		}
		await store.receive(\.commitDetail.filesLoaded) {
			$0.commitDetail?.isLoadingFiles = false
		}
		await store.receive(\.commitDetail.fileSelected)
	}

	// MARK: - Selecting

	@Test("tapping a commit opens its detail pane and loads its files")
	func tappingACommitOpensItsDetail() async {
		let first = commit("aaa", parents: ["bbb"])
		let store = store(commits: [first, commit("bbb")])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(
				repositoryPath: Self.repositoryPath,
				commit: first
			)
		}
		await receiveEmptyDetailLoad(store)
	}

	@Test("tapping a different commit moves the detail pane to it")
	func tappingAnotherCommitSwitchesTheDetail() async {
		let first = commit("aaa", parents: ["bbb"])
		let second = commit("bbb")
		let store = store(commits: [first, second])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: first)
		}
		await receiveEmptyDetailLoad(store)

		await store.send(.commitTapped("bbb")) {
			$0.selectedCommitHash = "bbb"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: second)
		}
		await receiveEmptyDetailLoad(store)
	}

	@Test("re-tapping the selected commit keeps the loaded detail as it is")
	func reTappingTheSelectedCommitDoesNothing() async {
		let first = commit("aaa")
		let store = store(commits: [first])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: first)
		}
		await receiveEmptyDetailLoad(store)

		// No state change and no reload: the commit's content cannot have changed.
		await store.send(.commitTapped("aaa"))
	}

	@Test("tapping a commit that is not in the graph is ignored")
	func tappingAnUnknownCommitIsIgnored() async {
		let store = store(commits: [commit("aaa")])

		await store.send(.commitTapped("nope"))
	}

	// MARK: - Closing

	@Test("closing the detail pane clears the selection")
	func closingClearsTheSelection() async {
		let first = commit("aaa")
		let store = store(commits: [first])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: first)
		}
		await receiveEmptyDetailLoad(store)

		await store.send(.closeDetailButtonTapped) {
			$0.selectedCommitHash = nil
			$0.commitDetail = nil
		}
	}

	// MARK: - Reloading the graph

	@Test("a reload that still lists the selected commit keeps its detail open")
	func reloadKeepsAStillPresentSelection() async {
		let first = commit("aaa", parents: ["bbb"])
		let second = commit("bbb")
		let store = store(commits: [first, second])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: first)
		}
		await receiveEmptyDetailLoad(store)

		let reloaded = [commit("ccc", parents: ["aaa"]), first, second]
		await store.send(.commitsLoaded(reloaded)) {
			$0.isLoading = false
			$0.errorMessage = nil
			$0.canLoadMore = false
			$0.rows = GitGraphLayout.layout(commits: reloaded)
		}
	}

	@Test("a reload that drops the selected commit closes its detail")
	func reloadClearsAVanishedSelection() async {
		let first = commit("aaa")
		let store = store(commits: [first])

		await store.send(.commitTapped("aaa")) {
			$0.selectedCommitHash = "aaa"
			$0.commitDetail = CommitDetailReducer.State(repositoryPath: Self.repositoryPath, commit: first)
		}
		await receiveEmptyDetailLoad(store)

		let reloaded = [commit("zzz")]
		await store.send(.commitsLoaded(reloaded)) {
			$0.isLoading = false
			$0.errorMessage = nil
			$0.canLoadMore = false
			$0.rows = GitGraphLayout.layout(commits: reloaded)
			$0.selectedCommitHash = nil
			$0.commitDetail = nil
		}
	}
}
