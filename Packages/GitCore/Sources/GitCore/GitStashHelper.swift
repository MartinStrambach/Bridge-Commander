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

	/// The stash store lives in the common git directory, shared by all worktrees of a
	/// repository — so during a refresh burst the per-row checks coalesce into a single
	/// `git stash list` process per repository instead of one per worktree.
	private static let stashList = StashListRunner()

	/// Checks if there is a stash on the specified branch
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - branch: The branch name to check for stashes
	/// - Returns: true if a stash exists on the branch, false otherwise
	public static func checkHasStashOnBranch(at path: String, branch: String) async -> Bool {
		guard let output = await stashList.run(at: path) else {
			return false
		}

		// Check if any stash entry contains the current branch
		// Format: "stash@{0}: WIP on branch-name: commit-hash commit-message"
		// or "stash@{0}: On branch-name: commit-hash commit-message"
		return output.split(separator: "\n").contains { line in
			line.contains("WIP on \(branch):") || line.contains("On \(branch):")
		}
	}
}

// MARK: -

/// Coalesces concurrent `git stash list` runs keyed by the repository's common git
/// directory. Results are intentionally not cached beyond the in-flight call — stashes
/// change at any time, so every new request gets fresh data.
private actor StashListRunner {
	private var inFlight: [String: Task<String?, Never>] = [:]

	/// Returns the trimmed `git stash list` output, or nil when the command fails.
	func run(at path: String) async -> String? {
		let key = GitDirectoryResolver.resolveCommonGitDirectory(at: path) ?? path
		if let existing = inFlight[key] {
			return await existing.value
		}

		let task = Task<String?, Never> { @concurrent in
			let result = await ProcessRunner.runGit(
				arguments: ["stash", "list"],
				at: path
			)
			return result.success ? result.trimmedOutput : nil
		}
		inFlight[key] = task

		let output = await task.value
		// Only clear our own entry — a waiter resuming late must not evict a newer in-flight task.
		if inFlight[key] == task {
			inFlight[key] = nil
		}
		return output
	}
}
