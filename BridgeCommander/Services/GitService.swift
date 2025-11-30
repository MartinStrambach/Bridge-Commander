import Foundation

// MARK: - Git Service

struct GitService: GitServiceType, Sendable {

	func getCurrentBranch(at path: String) async
	-> (branch: String, isMerge: Bool, unstagedCount: Int, stagedCount: Int) {
		let branch = GitBranchDetector.getCurrentBranch(at: path) ?? "unknown"
		let isMerge = GitMergeDetector.isGitOperationInProgress(at: path)
		let changes = await GitStatusDetector.getChangesCount(at: path)

		return (
			branch: branch,
			isMerge: isMerge,
			unstagedCount: changes.unstagedCount,
			stagedCount: changes.stagedCount
		)
	}

	func countUnpushedCommits(at path: String) async -> Int {
		await GitBranchDetector.countUnpushedCommits(at: path)
	}

	func mergeMaster(at path: String) async throws {
		try await GitMergeMasterHelper.mergeMaster(at: path)
	}
}
