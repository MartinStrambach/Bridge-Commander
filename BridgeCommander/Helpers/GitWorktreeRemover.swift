import Foundation

nonisolated enum GitWorktreeRemover {

	/// Removes a Git worktree at the specified path
	/// - Parameters:
	///   - name: The name of the worktree
	///   - path: The path to the Git worktree
	///   - force: Whether to force removal even if there are uncommitted changes
	/// - Throws: An error if the removal fails
	static func removeWorktree(name: String, path: String, force: Bool = false) async throws {
		let forceFlag = force ? "--force" : ""
		let script = """
		branch="\(name)"
		folder="../${branch//\\//_}"

		if git worktree list | grep -q "$folder"; then
		  echo "→ Removing worktree at: $folder"
		  git worktree remove \(forceFlag) "$folder"
		else
		  echo "❌ No worktree found for: $branch ($folder)" >&2
		  exit 1
		fi
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(filePath: "/bin/sh"),
			arguments: ["-c", script],
			currentDirectory: URL(filePath: path),
			environment: GitEnvironmentHelper.setupEnvironment()
		)

		guard result.success else {
			let msg = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw WorktreeRemovalError.removalFailed(message: msg.isEmpty ? "Unknown error" : msg)
		}
	}
}

// MARK: - Error Types

enum WorktreeRemovalError: LocalizedError, Sendable {
	case removalFailed(message: String)

	var errorDescription: String? {
		switch self {
		case let .removalFailed(message):
			"Failed to remove worktree: \(message)"
		}
	}
}
