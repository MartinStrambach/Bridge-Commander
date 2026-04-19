import Foundation
import ProcessExecution

public nonisolated enum GitWorktreeCreator {

	/// Computes the destination folder for a new worktree, mirroring the
	/// sanitization done by the shell script below.
	public static func worktreeFolder(
		repositoryPath: String,
		branchName: String,
		baseBranch: String,
		createNewBranch: Bool,
		worktreeBasePath: String
	) -> URL {
		let repoURL = URL(fileURLWithPath: repositoryPath)
		let repoName = repoURL.lastPathComponent

		let baseURL: URL = {
			if worktreeBasePath.hasPrefix("/") {
				return URL(fileURLWithPath: worktreeBasePath)
			}
			return URL(fileURLWithPath: worktreeBasePath, relativeTo: repoURL).standardizedFileURL
		}()

		let source = createNewBranch ? branchName : baseBranch
		let sanitized = source
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: ".", with: "_")

		return baseURL
			.appendingPathComponent(repoName)
			.appendingPathComponent(sanitized)
	}

	/// Creates a new Git worktree with the specified branch name.
	/// Returns the absolute URL of the created worktree.
	public static func createWorktree(
		branchName: String,
		baseBranch: String,
		repositoryPath: String,
		createNewBranch: Bool = true,
		worktreeBasePath: String = "../worktrees"
	) async throws -> URL {
		let folder = worktreeFolder(
			repositoryPath: repositoryPath,
			branchName: branchName,
			baseBranch: baseBranch,
			createNewBranch: createNewBranch,
			worktreeBasePath: worktreeBasePath
		)

		let script = """
		set -e

		# Fetch from origin
		echo "→ Fetching from origin..."
		git fetch origin

		branch="$1";
		base_branch="$2";
		create_new_branch="$3";
		folder="$4";

		mkdir -p "$(dirname "$folder")"

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
			arguments: [
				"-c",
				script,
				"-s",
				branchName,
				baseBranch,
				createNewBranch ? "true" : "false",
				folder.path
			],
			currentDirectory: URL(fileURLWithPath: repositoryPath),
			environment: EnvironmentHelper.setupEnvironment()
		)

		guard result.success else {
			let msg = result.trimmedError
			throw GitError.worktreeCreationFailed(msg.isEmpty ? "Unknown error" : msg)
		}

		return folder
	}
}
