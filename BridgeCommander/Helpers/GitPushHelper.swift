import Foundation

nonisolated enum GitPushHelper {
	struct PushResult: Equatable {
		let isUpToDate: Bool
		let message: String
	}

	/// Pushes commits to the remote repository
	/// - Parameter path: The path to the Git repository
	/// - Returns: PushResult with information about the push operation
	/// - Throws: PushError if the push fails
	static func push(at path: String) async throws -> PushResult {
		let result = await ProcessRunner.runGit(
			arguments: ["push"],
			at: path
		)

		let output = result.trimmedOutput
		let errorOutput = result.trimmedError

		guard result.success else {
			throw GitError.pushFailed(errorOutput)
		}

		// Check if everything is up to date
		let combinedOutput = output + errorOutput
		let isUpToDate = combinedOutput.contains("Everything up-to-date")

		return PushResult(
			isUpToDate: isUpToDate,
			message: combinedOutput
		)
	}
}

