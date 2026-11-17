import ActivityLog
import Foundation
import ProcessExecution

public nonisolated enum GitWorktreeRemover {

	public enum Outcome: Equatable, Sendable {
		/// The worktree and its folder are gone.
		case removed
		/// Git took the worktree out of the repository but could not delete every file under it;
		/// what it could not delete is still in the folder. Carries git's message.
		case removedLeavingFiles(String)
	}

	/// Removes a Git worktree at the specified path
	/// - Parameters:
	///   - name: The name of the worktree
	///   - path: The path to the Git worktree
	///   - force: Whether to force removal even if there are uncommitted changes
	/// - Returns: Whether the folder went with the worktree. `git worktree remove` deletes the
	///   files first and unregisters the worktree whether or not that worked ("there's no going
	///   back from here", in its source), exiting with an error if it did not — so a failed exit
	///   alone does not say the worktree is still there.
	/// - Throws: An error if the worktree is still there: git refused before touching it.
	@discardableResult
	public static func removeWorktree(name: String, path: String, force: Bool = false) async throws -> Outcome {
		// Resolved now: the folder's `.git` pointer is dead once git has unregistered the worktree.
		let mainRepositoryPath = GitDirectoryResolver.resolveMainRepositoryPath(at: path)
		var wasRegistered = false
		if let mainRepositoryPath {
			wasRegistered = await isRegistered(path, in: mainRepositoryPath) == true
		}

		let forceFlag = force ? "--force" : ""
		let script = """
		folder="\(path)"

		if git worktree list | grep -qF "$folder"; then
		  echo "→ Removing worktree at: $folder"
		  git worktree remove \(forceFlag) "$folder"
		else
		  echo "No worktree found at: $folder" >&2
		  exit 1
		fi
		"""

		let start = ContinuousClock.now
		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", script],
			currentDirectory: URL(filePath: path),
			environment: EnvironmentHelper.setupEnvironment()
		)
		// The script's git calls bypass `runGit`, so the removal is recorded here.
		ActivityLog.shared.record(
			result.success ? .git : .error,
			"worktree remove \(force ? "--force " : "")\(path) → exit \(result.exitCode) in \((ContinuousClock.now - start).activityLogDescription)",
			details: result.success ? nil : result.trimmedError
		)

		guard result.success else {
			let msg = result.trimmedError
			let message = msg.isEmpty ? "Unknown error" : msg
			if wasRegistered, let mainRepositoryPath, await isRegistered(path, in: mainRepositoryPath) == false {
				return .removedLeavingFiles(message)
			}
			throw GitError.worktreeRemovalFailed(message)
		}

		return .removed
	}

	/// Whether git lists `path` among the worktrees of the repository at `mainRepositoryPath`;
	/// nil when the list cannot be read.
	private static func isRegistered(_ path: String, in mainRepositoryPath: String) async -> Bool? {
		let worktrees = await GitWorktreeScanner.listWorktrees(forRepo: mainRepositoryPath)
		// The main repository is always listed, so an empty list is a failed one.
		guard !worktrees.isEmpty else {
			return nil
		}

		// Git lists resolved paths; the caller's may go through a symlink.
		let resolved = URL(filePath: path).resolvingSymlinksInPath().path
		return worktrees.contains {
			$0.path == path || URL(filePath: $0.path).resolvingSymlinksInPath().path == resolved
		}
	}
}
