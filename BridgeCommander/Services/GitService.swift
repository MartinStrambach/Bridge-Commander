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
	var mergeMaster: @Sendable (_ at: String) async throws -> GitMergeHelper.MergeResult
	var pull: @Sendable (_ at: String) async throws -> GitPullHelper.PullResult
	var fetch: @Sendable (_ at: String) async throws -> GitFetchHelper.FetchResult
}

extension GitClient: DependencyKey {
	static let liveValue = GitClient(
		getCurrentBranch: { at in
			// A single git status --porcelain=v2 --branch call returns branch name,
			// staged count, and unstaged count — replacing separate file reads and
			// two parallel git invocations.
			let status = await GitStatusDetector.getBranchAndChanges(at: at)
			let isMerge = GitMergeDetector.isGitOperationInProgress(at: at)
			return (
				branch: status.branch ?? "unknown",
				unstagedCount: isMerge ? 0 : status.unstagedCount,
				stagedCount: isMerge ? 0 : status.stagedCount
			)
		},
		countUnpushedCommits: { at in
			await GitBranchDetector.countUnpushedCommits(at: at)
		},
		countCommitsBehind: { at in
			await GitBranchDetector.countCommitsBehind(at: at)
		},
		mergeMaster: { at in
			try await GitMergeHelper.mergeMaster(at: at)
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
