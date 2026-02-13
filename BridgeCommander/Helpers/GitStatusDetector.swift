import Foundation

struct GitChanges: Sendable {
	let unstagedCount: Int
	let stagedCount: Int
}

nonisolated enum GitStatusDetector {

	/// Detects both staged and unstaged changes in a repository
	/// Uses `git ls-files -m` for unstaged changes and `git diff --name-only --cached` for staged changes
	/// - Parameter path: The path to the Git repository
	/// - Returns: A GitChanges struct with both counts
	static func getChangesCount(at path: String) async -> GitChanges {
		async let unstaged = getUnstagedCount(at: path)
		async let staged = getStagedCount(at: path)

		return await GitChanges(
			unstagedCount: unstaged,
			stagedCount: staged
		)
	}

	/// Counts unstaged changes using git ls-files -m
	private static func getUnstagedCount(at path: String) async -> Int {
		let result = await ProcessRunner.runGit(
			arguments: ["ls-files", "-mdo", "--exclude-standard", "--exclude=*/submodules/*"],
			at: path
		)

		let output = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		return output.isEmpty ? 0 : output.split(separator: "\n").count
	}

	/// Counts staged changes using git diff --name-only --cached
	private static func getStagedCount(at path: String) async -> Int {
		let result = await ProcessRunner.runGit(
			arguments: ["diff", "--name-only", "--cached"],
			at: path
		)

		let output = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		return output.isEmpty ? 0 : output.split(separator: "\n").count
	}
}
