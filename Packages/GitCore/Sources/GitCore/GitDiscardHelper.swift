import Foundation
import ProcessExecution

/// Discards local working-tree changes via `git reset --hard` (+ `git clean -fd`).
public nonisolated enum GitDiscardHelper {
	/// Reverts all staged and unstaged changes to tracked files. Leaves untracked files in place.
	public static func discardTracked(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["reset", "--hard"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.discardFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	/// Reverts tracked changes and deletes untracked files/directories. Leaves ignored files alone.
	public static func discardAll(at path: String) async throws {
		try await discardTracked(at: path)
		let result = await ProcessRunner.runGit(
			arguments: ["clean", "-fd"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.discardFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}
}
