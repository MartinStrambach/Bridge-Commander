import ActivityLog
import Foundation
import ProcessExecution

public nonisolated enum GitWorktreeRemover {

	/// Removes a Git worktree at the specified path
	/// - Parameters:
	///   - name: The name of the worktree
	///   - path: The path to the Git worktree
	///   - force: Whether to force removal even if there are uncommitted changes
	/// - Throws: An error if the removal fails
	public static func removeWorktree(name: String, path: String, force: Bool = false) async throws {
		let forceFlag = force ? "--force" : ""
		let script = """
		folder="\(path)"

		if git worktree list | grep -qF "$folder"; then
		  echo "→ Removing worktree at: $folder"
		  git worktree remove \(forceFlag) "$folder"
		else
		  echo "❌ No worktree found at: $folder" >&2
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
			throw GitError.worktreeRemovalFailed(msg.isEmpty ? "Unknown error" : msg)
		}
	}
}
