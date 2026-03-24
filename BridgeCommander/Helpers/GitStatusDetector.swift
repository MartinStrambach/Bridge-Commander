import Foundation

struct GitBranchAndChanges: Sendable {
	let branch: String?
	let unstagedCount: Int
	let stagedCount: Int
}

nonisolated enum GitStatusDetector {

	/// Returns branch name, staged count, and unstaged count in a single git invocation.
	/// Uses `git status --porcelain=v2 --branch` which outputs both branch info and file status.
	/// - Parameter path: The path to the Git repository
	/// - Returns: A GitBranchAndChanges struct with branch name and both counts
	static func getBranchAndChanges(at path: String) async -> GitBranchAndChanges {
		let result = await ProcessRunner.runGit(
			arguments: ["status", "--porcelain=v2", "--branch"],
			at: path
		)

		guard result.success else {
			return GitBranchAndChanges(branch: nil, unstagedCount: 0, stagedCount: 0)
		}

		var branch: String?
		var unstagedCount = 0
		var stagedCount = 0

		for line in result.outputString.split(separator: "\n", omittingEmptySubsequences: true) {
			if line.hasPrefix("# branch.head ") {
				let name = String(line.dropFirst("# branch.head ".count))
				if name != "(detached)" {
					branch = name
				}
			} else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
				// Ordinary changed entry: "1 XY ..."
				// XY = two-letter status: X = staged, Y = unstaged
				// Each character is one of ' ', 'M', 'A', 'D', 'R', 'C', 'U'
				let parts = line.split(separator: " ", maxSplits: 2)
				guard parts.count >= 2 else { continue }
				let xy = parts[1]
				guard xy.count >= 2 else { continue }
				let x = xy[xy.startIndex]  // staged status
				let y = xy[xy.index(after: xy.startIndex)]  // unstaged status
				if x != "." { stagedCount += 1 }
				if y != "." { unstagedCount += 1 }
			} else if line.hasPrefix("? ") {
				// Untracked file
				unstagedCount += 1
			} else if line.hasPrefix("u ") {
				// Unmerged entry — counts as unstaged
				unstagedCount += 1
			}
		}

		return GitBranchAndChanges(branch: branch, unstagedCount: unstagedCount, stagedCount: stagedCount)
	}

}
