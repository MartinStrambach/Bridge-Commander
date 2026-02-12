import Foundation

enum GitWorktreeCreator {

	/// Creates a new Git worktree with the specified branch name
	/// - Parameters:
	///   - branchName: The name of the new branch to create
	///   - baseBranch: The base branch to create the worktree from (defaults to current branch)
	///   - repositoryPath: The path to the Git repository
	/// - Throws: An error if the creation fails
	static func createWorktree(branchName: String, baseBranch: String, repositoryPath: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let script = """
			set -e

			# Fetch from origin
			echo "→ Fetching from origin..."
			git fetch origin

			branch="$1";
			base_branch="$2";

			# Sanitize branch name for folder (replace / and . with _)
			temp="${1//\\//_}"
			folder="../${temp//./_}"

			# Check if worktree already exists (exact match)
			if git worktree list | grep -qw "$folder"; then
			  echo "❌ Worktree already exists at: $folder" >&2
			  exit 1
			fi

			# Check if the new branch already exists
			if git show-ref --quiet "refs/heads/$branch"; then
			 echo "❌ Branch '$branch' already exists locally" >&2
			 exit 1
			fi

			# Determine the correct base reference
			if git show-ref --quiet "refs/heads/$base_branch"; then
			 # Base branch exists locally
			 base_ref="$base_branch"
			 echo "→ Using local base branch: $base_branch"
			elif git show-ref --quiet "refs/remotes/origin/$base_branch"; then
			 # Base branch exists remotely but not locally
			 base_ref="origin/$base_branch"
			 echo "→ Using remote base branch: $base_ref"
			else
			 echo "❌ Base branch '$base_branch' not found locally or remotely" >&2
			 exit 1
			fi

			# Create worktree with new branch based on base reference
			echo "→ Creating worktree at: $folder with new branch '$branch' from $base_ref"
			git worktree add "$folder" -b "$branch" "$base_ref"
			echo "✅ Worktree created successfully with branch '$branch' from $base_ref"
			"""
			let process = Process()
			process.currentDirectoryURL = URL(fileURLWithPath: repositoryPath)
			process.executableURL = URL(fileURLWithPath: "/bin/sh")
			process.arguments = ["-c", script, "-s", branchName, baseBranch]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			let outputCollector = PipeDataCollector()
			let errorCollector = PipeDataCollector()

			// Continuously read from output pipe in background to prevent buffer overflow
			outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				outputCollector.append(data)
			}

			// Continuously read from error pipe in background to prevent buffer overflow
			errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				errorCollector.append(data)
			}

			process.terminationHandler = { proc in
				// Stop reading from pipes
				outputPipe.fileHandleForReading.readabilityHandler = nil
				errorPipe.fileHandleForReading.readabilityHandler = nil

				// Read any remaining data
				let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
				let remainingError = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()

				// Combine all output
				outputCollector.append(remainingOutput)
				errorCollector.append(remainingError)

				if proc.terminationStatus == 0 {
					continuation.resume()
				}
				else {
					let errorData = errorCollector.getData()
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
