import Foundation

enum GitAbortMergeHelper {
	/// Aborts an ongoing merge operation
	/// - Parameter path: The path to the Git repository
	/// - Throws: An error if the abort fails
	@concurrent
	static func abortMerge(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["merge", "--abort"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { proc in
				if proc.terminationStatus == 0 {
					continuation.resume()
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? "Unknown error"

					continuation.resume(throwing: AbortMergeError.abortFailed(message: errorMessage))
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: error)
			}
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
