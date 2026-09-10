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

	/// Restores a stash and leaves it in the stash list.
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - reference: The `stash@{n}` reference to apply. Passed explicitly rather than
	///     letting git default to `stash@{0}`: the stash list is shared by every worktree
	///     of a repository, so the newest entry often belongs to a different branch than
	///     the one whose menu the user opened.
	/// - Throws: GitError if the operation fails
	public static func stashApply(at path: String, reference: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "apply", reference],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.stashApplyFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	/// Restores a stash and drops it from the stash list.
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - reference: The `stash@{n}` reference to pop — see `stashApply(at:reference:)`
	///     for why it is never left implicit.
	/// - Throws: GitError if the operation fails
	public static func stashPop(at path: String, reference: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "pop", reference],
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

	/// Finds the newest stash taken on the given branch.
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - branch: The branch name to look for
	/// - Returns: The matching entry, or nil when the branch has no stash (or the list
	///   could not be read)
	public static func findStash(at path: String, branch: String) async -> GitStashEntry? {
		guard let output = await stashList.run(at: path) else {
			return nil
		}

		return GitStashListParser.newestEntry(on: branch, in: GitStashListParser.parse(output))
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
