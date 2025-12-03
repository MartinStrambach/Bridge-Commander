import Foundation

enum GitPushHelper {
	struct PushResult: Equatable {
		let isUpToDate: Bool
		let message: String
	}

	/// Pushes commits to the remote repository
	/// - Parameter path: The path to the Git repository
	/// - Returns: PushResult with information about the push operation
	/// - Throws: PushError if the push fails
	static func push(at path: String) async throws -> PushResult {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["push"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { proc in
				let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
				let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

				let output = String(data: outputData, encoding: .utf8)?
					.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				let errorOutput = String(data: errorData, encoding: .utf8)?
					.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

				if proc.terminationStatus == 0 {
					// Check if everything is up to date
					let combinedOutput = output + errorOutput
					let isUpToDate = combinedOutput.contains("Everything up-to-date")

					let result = PushResult(
						isUpToDate: isUpToDate,
						message: combinedOutput
					)
					continuation.resume(returning: result)
				}
				else {
					continuation.resume(throwing: PushError.pushFailed(message: errorOutput))
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

enum PushError: LocalizedError, Equatable {
	case pushFailed(message: String)

	var errorDescription: String? {
		switch self {
		case let .pushFailed(message):
			"Failed to push: \(message)"
		}
	}
}
