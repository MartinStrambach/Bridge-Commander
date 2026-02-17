import Foundation

nonisolated enum GitWorktreeCreator {

	/// Creates a new Git worktree with the specified branch name
	/// - Parameters:
	///   - branchName: The name of the new branch to create
	///   - baseBranch: The base branch to create the worktree from (defaults to current branch)
	///   - repositoryPath: The path to the Git repository
	///   - createNewBranch: When true, creates a new branch; when false, checks out the base branch directly
	/// - Throws: An error if the creation fails
	static func createWorktree(
		branchName: String,
		baseBranch: String,
		repositoryPath: String,
		createNewBranch: Bool = true
	) async throws {
		let script = """
		set -e

		# Fetch from origin
		echo "→ Fetching from origin..."
		git fetch origin

		branch="$1";
		base_branch="$2";
		create_new_branch="$3";

		# Sanitize name for folder (replace / and . with _)
		if [ "$create_new_branch" = "true" ]; then
		  temp="${branch//\\//_}"
		else
		  temp="${base_branch//\\//_}"
		fi
		folder="../${temp//./_}"

		# Check if worktree already exists (exact match)
		if git worktree list | grep -qw "$folder"; then
		  echo "❌ Worktree already exists at: $folder" >&2
		  exit 1
		fi

		# Check if the new branch already exists (only when creating a new branch)
		if [ "$create_new_branch" = "true" ]; then
		  if git show-ref --quiet "refs/heads/$branch"; then
		    echo "❌ Branch '$branch' already exists locally" >&2
		    exit 1
		  fi
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

		# Create worktree
		if [ "$create_new_branch" = "true" ]; then
		  echo "→ Creating worktree at: $folder with new branch '$branch' from $base_ref"
		  git worktree add "$folder" -b "$branch" "$base_ref"
		  echo "✅ Worktree created successfully with branch '$branch' from $base_ref"
		else
		  # When base branch is remote-only, create a local tracking branch to avoid detached HEAD
		  if git show-ref --quiet "refs/heads/$base_branch"; then
		    echo "→ Creating worktree at: $folder on local branch $base_branch"
		    git worktree add "$folder" "$base_branch"
		  else
		    echo "→ Creating worktree at: $folder with local tracking branch '$base_branch' from $base_ref"
		    git worktree add "$folder" -b "$base_branch" "$base_ref"
		  fi
		  echo "✅ Worktree created successfully on branch $base_branch"
		fi
		"""

		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/bin/sh"),
			arguments: ["-c", script, "-s", branchName, baseBranch, createNewBranch ? "true" : "false"],
			currentDirectory: URL(fileURLWithPath: repositoryPath),
			environment: GitEnvironmentHelper.setupEnvironment()
		)

		guard result.success else {
			let msg = result.trimmedError
			throw GitError.worktreeCreationFailed(msg.isEmpty ? "Unknown error" : msg)
		}
	}
}
