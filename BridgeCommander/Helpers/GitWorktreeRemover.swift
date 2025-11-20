import Foundation

enum GitWorktreeRemover {

	/// Removes a Git worktree at the specified path
	/// - Parameter path: The path to the Git worktree
	/// - Throws: An error if the removal fails
	static func removeWorktree(at path: String) throws {
		let process = Process()
		process.currentDirectoryPath = path
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")

		process.arguments = ["worktree", "remove", path]

		let pipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = pipe
		process.standardError = errorPipe

		try process.run()
		process.waitUntilExit()

		if process.terminationStatus != 0 {
			let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
			let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
			throw WorktreeRemovalError
				.removalFailed(message: errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
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
