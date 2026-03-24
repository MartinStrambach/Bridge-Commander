import Foundation

nonisolated enum GitWorktreeScanner {

	/// Lists all worktrees for a given repository using `git worktree list --porcelain`
	/// - Parameter repositoryPath: The path to the main Git repository
	/// - Returns: An array of ScannedRepository entries (main repo first, then worktrees)
	static func listWorktrees(forRepo repositoryPath: String) async -> [ScannedRepository] {
		let result = await ProcessRunner.runGit(
			arguments: ["worktree", "list", "--porcelain"],
			at: repositoryPath
		)

		guard result.success else {
			return []
		}

		let output = result.outputString
		let blocks = output.components(separatedBy: "\n\n")

		var repositories: [ScannedRepository] = []

		for (index, block) in blocks.enumerated() {
			let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else {
				continue
			}
			guard let worktreePath = extractValue(from: trimmed, prefix: "worktree ") else {
				continue
			}

			let isWorktree = index != 0
			let url = URL(fileURLWithPath: worktreePath)
			let name = url.lastPathComponent
			let directory = url.deletingLastPathComponent().path

			// Branch name is available directly in the porcelain block as
			// "branch refs/heads/<name>" — no extra file I/O needed.
			let branchName = extractBranch(from: trimmed)
			let mergeInProgress = GitMergeDetector.isGitOperationInProgress(at: worktreePath)

			let repo = ScannedRepository(
				path: worktreePath,
				name: name,
				directory: directory,
				isWorktree: isWorktree,
				branchName: branchName,
				isMergeInProgress: mergeInProgress
			)
			repositories.append(repo)
		}

		return repositories
	}

	private static func extractValue(from block: String, prefix: String) -> String? {
		for line in block.components(separatedBy: "\n") {
			if line.hasPrefix(prefix) {
				return String(line.dropFirst(prefix.count))
			}
		}
		return nil
	}

	/// Parses the branch name from a `git worktree list --porcelain` block.
	/// Returns nil if the worktree is in detached HEAD state.
	private static func extractBranch(from block: String) -> String? {
		guard let ref = extractValue(from: block, prefix: "branch ") else {
			return nil
		}
		let headsPrefix = "refs/heads/"
		guard ref.hasPrefix(headsPrefix) else {
			return nil
		}
		return String(ref.dropFirst(headsPrefix.count))
	}
}
