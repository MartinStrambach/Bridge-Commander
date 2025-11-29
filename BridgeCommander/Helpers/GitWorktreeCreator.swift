import Foundation

enum GitWorktreeCreator {

	/// Creates a new Git worktree with the specified branch name
	/// - Parameters:
	///   - branchName: The name of the new branch to create
	///   - repositoryPath: The path to the Git repository
	/// - Throws: An error if the creation fails
	static func createWorktree(branchName: String, repositoryPath: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let script = """
			set -e

			# Fetch from origin
			echo "→ Fetching from origin..."
			git fetch origin

			branch="$1";

			# Sanitize branch name for folder (replace / and . with _)
			temp="${1//\\//_}"
			folder="../${temp//./_}"

			# Check if worktree already exists (exact match)
			if git worktree list | grep -qw "$folder"; then
			  echo "❌ Worktree already exists at: $folder" >&2
			  exit 1
			fi

			# Create worktree
			echo "→ Creating worktree at: $folder"
			if git show-ref --quiet "refs/heads/$branch"; then
			 git worktree add "$folder" "$branch";
			 echo "✅ Worktree from remote branch created successfully"
			else
			 git worktree add "$folder" -b "$branch";
			 echo "✅ Worktree new branch created successfully"
			fi
			"""
			let process = Process()
			process.currentDirectoryPath = repositoryPath
			process.executableURL = URL(fileURLWithPath: "/bin/sh")
			process.arguments = ["-c", script, "-s", branchName]

			// Set up environment with PATH from user's shell
			var environment = ProcessInfo.processInfo.environment
			if let path = environment["PATH"] {
				environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
			}
			process.environment = environment

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

					continuation.resume(throwing: WorktreeCreationError.creationFailed(message: msg))
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

enum WorktreeCreationError: LocalizedError {
	case creationFailed(message: String)

	var errorDescription: String? {
		switch self {
		case let .creationFailed(message):
			"Failed to create worktree: \(message)"
		}
	}
}
