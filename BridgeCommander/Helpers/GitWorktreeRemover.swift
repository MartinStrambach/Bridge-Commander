import Foundation

enum GitWorktreeRemover {

	/// Removes a Git worktree at the specified path
	/// - Parameter path: The path to the Git worktree
	/// - Throws: An error if the removal fails
	static func removeWorktree(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["worktree", "remove", path]

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
					let msg = String(data: errorData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? "Unknown error"

					continuation.resume(throwing: WorktreeRemovalError.removalFailed(message: msg))
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

enum WorktreeRemovalError: LocalizedError {
	case removalFailed(message: String)

	var errorDescription: String? {
		switch self {
		case let .removalFailed(message):
			"Failed to remove worktree: \(message)"
		}
	}
}
