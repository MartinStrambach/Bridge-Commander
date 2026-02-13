import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Service

@DependencyClient
nonisolated struct GitClient: Sendable {
	var getCurrentBranch: @Sendable (_ at: String) async -> (
		branch: String, unstagedCount: Int, stagedCount: Int
	) = { _ in ("", 0, 0) }
	var countUnpushedCommits: @Sendable (_ at: String) async -> Int = { _ in 0 }
	var countCommitsBehind: @Sendable (_ at: String) async -> Int = { _ in 0 }
	var mergeMaster: @Sendable (_ at: String) async throws -> GitMergeMasterHelper.MergeResult
	var pull: @Sendable (_ at: String) async throws -> GitPullHelper.PullResult
	var fetch: @Sendable (_ at: String) async throws -> GitFetchHelper.FetchResult
}

extension GitClient: DependencyKey {
	static let liveValue = GitClient(
		getCurrentBranch: { at in
			let branch = GitBranchDetector.getCurrentBranch(at: at) ?? "unknown"
			let isMerge = GitMergeDetector.isGitOperationInProgress(at: at)
			let changes =
				if isMerge {
					GitChanges(unstagedCount: 0, stagedCount: 0)
				}
				else {
					await GitStatusDetector.getChangesCount(at: at)
				}

			return (
				branch: branch,
				unstagedCount: changes.unstagedCount,
				stagedCount: changes.stagedCount
			)
		},
		countUnpushedCommits: { at in
			await GitBranchDetector.countUnpushedCommits(at: at)
		},
		countCommitsBehind: { at in
			await GitBranchDetector.countCommitsBehind(at: at)
		},
		mergeMaster: { at in
			try await GitMergeMasterHelper.mergeMaster(at: at)
		},
		pull: { at in
			try await GitPullHelper.pull(at: at)
		},
		fetch: { at in
			try await GitFetchHelper.fetch(at: at)
		}
	)
}

extension GitClient: TestDependencyKey {
	static let testValue = GitClient()
}
