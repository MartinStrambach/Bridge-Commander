import Foundation

nonisolated enum GitWorktreeCreator {

	/// Creates a new Git worktree with the specified branch name
	/// - Parameters:
	///   - branchName: The name of the new branch to create
	///   - baseBranch: The base branch to create the worktree from (defaults to current branch)
	///   - repositoryPath: The path to the Git repository
	/// - Throws: An error if the creation fails
	static func createWorktree(branchName: String, baseBranch: String, repositoryPath: String) async throws {
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

		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/sh"),
			arguments: ["-c", script, "-s", branchName, baseBranch],
			currentDirectory: URL(fileURLWithPath: repositoryPath),
			environment: GitEnvironmentHelper.setupEnvironment()
		)

		guard result.success else {
			let msg = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw WorktreeCreationError.creationFailed(message: msg.isEmpty ? "Unknown error" : msg)
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
