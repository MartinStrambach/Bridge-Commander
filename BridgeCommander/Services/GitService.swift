import Foundation

// MARK: - Git Service

struct GitService: GitServiceType, Sendable {

	func getCurrentBranch(at path: String) async
	-> (branch: String, unstagedCount: Int, stagedCount: Int) {
		let branch = GitBranchDetector.getCurrentBranch(at: path) ?? "unknown"
		let isMerge = GitMergeDetector.isGitOperationInProgress(at: path)
		let changes =
			if isMerge {
				GitChanges(unstagedCount: 0, stagedCount: 0)
			}
			else {
				await GitStatusDetector.getChangesCount(at: path)
			}

		return (
			branch: branch,
			unstagedCount: changes.unstagedCount,
			stagedCount: changes.stagedCount
		)
	}

	func countUnpushedCommits(at path: String) async -> Int {
		await GitBranchDetector.countUnpushedCommits(at: path)
	}

	func countCommitsBehind(at path: String) async -> Int {
		await GitBranchDetector.countCommitsBehind(at: path)
	}

	func mergeMaster(at path: String) async throws {
		try await GitMergeMasterHelper.mergeMaster(at: path)
	}

	func pull(at path: String) async throws -> GitPullHelper.PullResult {
		try await GitPullHelper.pull(at: path)
	}

	func fetch(at path: String) async throws -> GitFetchHelper.FetchResult {
		try await GitFetchHelper.fetch(at: path)
	}
}
