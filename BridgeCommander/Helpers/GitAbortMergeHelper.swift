import Foundation

enum GitAbortMergeHelper {
	/// Aborts an ongoing merge operation
	/// - Parameter path: The path to the Git repository
	/// - Throws: An error if the abort fails
	static func abortMerge(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["merge", "--abort"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw AbortMergeError.abortFailed(message: errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}
}

// MARK: - Error Types

enum AbortMergeError: LocalizedError {
	case abortFailed(message: String)

	var errorDescription: String? {
		switch self {
		case let .abortFailed(message):
			"Failed to abort merge: \(message)"
		}
	}
}
