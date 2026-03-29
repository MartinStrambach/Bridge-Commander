import Foundation
import ProcessExecution

public nonisolated enum GitStashHelper {
	/// Stashes changes including untracked files
	/// - Parameter path: The path to the Git repository
	/// - Throws: GitError if the operation fails
	public static func stash(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "-u"], // Include untracked files
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.stashFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	/// Pops the most recent stash
	/// - Parameter path: The path to the Git repository
	/// - Throws: GitError if the operation fails
	public static func stashPop(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "pop"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.stashPopFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	/// Checks if there is a stash on the specified branch
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - branch: The branch name to check for stashes
	/// - Returns: true if a stash exists on the branch, false otherwise
	public static func checkHasStashOnBranch(at path: String, branch: String) async -> Bool {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "list"],
			at: path
		)

		guard result.success else {
			return false
		}

		let output = result.trimmedOutput

		// Check if any stash entry contains the current branch
		// Format: "stash@{0}: WIP on branch-name: commit-hash commit-message"
		// or "stash@{0}: On branch-name: commit-hash commit-message"
		return output.split(separator: "\n").contains { line in
			line.contains("WIP on \(branch):") || line.contains("On \(branch):")
		}
	}
}
