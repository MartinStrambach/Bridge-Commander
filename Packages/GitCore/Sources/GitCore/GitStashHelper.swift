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
	///   - entry: The stash to apply. Named explicitly rather than letting git default to
	///     `stash@{0}`: the stash list is shared by every worktree of a repository, so the
	///     newest entry often belongs to a different branch than the one whose menu the user
	///     opened. Looked up again first (`currentReference(of:at:)`), as its index may have
	///     moved since it was found.
	/// - Throws: GitError if the operation fails
	public static func stashApply(at path: String, entry: GitStashEntry) async throws {
		guard let reference = await currentReference(of: entry, at: path) else {
			throw GitError.stashApplyFailed(stashGoneMessage)
		}

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
	///   - entry: The stash to pop — see `stashApply(at:entry:)`.
	/// - Throws: GitError if the operation fails
	public static func stashPop(at path: String, entry: GitStashEntry) async throws {
		guard let reference = await currentReference(of: entry, at: path) else {
			throw GitError.stashPopFailed(stashGoneMessage)
		}

		let result = await ProcessRunner.runGit(
			arguments: ["stash", "pop", reference],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.stashPopFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	/// Drops a stash without restoring it.
	///
	/// Deliberately `git stash drop <ref>` rather than `git stash clear`: the stash list
	/// lives in the common git directory and is shared by every worktree of a repository,
	/// so clearing it would throw away work belonging to branches the user isn't looking at.
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - entry: The stash to drop — see `stashApply(at:entry:)`. Dropping by a stale index
	///     would throw away somebody else's stash.
	/// - Throws: GitError if the operation fails
	public static func stashDrop(at path: String, entry: GitStashEntry) async throws {
		guard let reference = await currentReference(of: entry, at: path) else {
			throw GitError.stashDropFailed(stashGoneMessage)
		}

		let result = await ProcessRunner.runGit(
			arguments: ["stash", "drop", reference],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.stashDropFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	private static let stashGoneMessage =
		"The stash is no longer in the stash list. It may have been applied or dropped in another worktree."

	/// The `stash@{n}` reference `entry` goes by now. The list is shared by every worktree, so
	/// a stash pushed or dropped in another one since `entry` was found shifts the indices, and
	/// the old reference would name a different stash. Read fresh, not through `stashList`: a
	/// coalesced run may have started before that change.
	/// - Returns: The reference, or nil when the entry is gone (or the list could not be read)
	static func currentReference(of entry: GitStashEntry, at path: String) async -> String? {
		let result = await ProcessRunner.runGit(
			arguments: ["stash", "list", GitStashListParser.listFormat],
			at: path
		)
		guard result.success else {
			return nil
		}

		return GitStashListParser.entry(matching: entry, in: GitStashListParser.parse(result.trimmedOutput))?
			.reference
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

	/// Returns the trimmed `git stash list` output (in `GitStashListParser.listFormat`), or nil
	/// when the command fails.
	func run(at path: String) async -> String? {
		let key = GitDirectoryResolver.resolveCommonGitDirectory(at: path) ?? path
		if let existing = inFlight[key] {
			return await existing.value
		}

		let task = Task<String?, Never> { @concurrent in
			let result = await ProcessRunner.runGit(
				arguments: ["stash", "list", GitStashListParser.listFormat],
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
