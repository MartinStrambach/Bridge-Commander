import Foundation

nonisolated enum GitAbortMergeHelper {
	/// Aborts an ongoing merge operation
	/// - Parameter path: The path to the Git repository
	/// - Throws: GitError if the abort fails
	static func abortMerge(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["merge", "--abort"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.abortMergeFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}
}
