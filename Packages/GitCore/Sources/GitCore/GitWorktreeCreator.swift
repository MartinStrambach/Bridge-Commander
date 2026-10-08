import ActivityLog
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
		  # --no-track: when $base_ref is a remote branch (origin/A), git would otherwise
		  # auto-configure the new branch to track origin/A. A later `git push` would then
		  # push commits straight into A instead of creating a new remote branch for the MR.
		  # Branching off a local base never sets up tracking, so this makes both paths consistent.
		  git worktree add "$folder" -b "$branch" --no-track "$base_ref"
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

		let start = ContinuousClock.now
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
		// The script's git calls bypass `runGit`, so the step is recorded here, with the script's
		// own account of which base it picked.
		let branch = createNewBranch ? "new branch \(branchName) from \(baseBranch)" : "branch \(baseBranch)"
		ActivityLog.shared.record(
			result.success ? .git : .error,
			"worktree add \(folder.path) on \(branch) (in \(repositoryPath)) → exit \(result.exitCode) in \((ContinuousClock.now - start).activityLogDescription)",
			details: result.success ? result.trimmedOutput : result.trimmedError
		)

		guard result.success else {
			let msg = result.trimmedError
			throw GitError.worktreeCreationFailed(msg.isEmpty ? "Unknown error" : msg)
		}

		return folder
	}

	/// Adds a worktree for a ref `origin` keeps but does not publish as a branch — a PR/MR from a
	/// fork, whose head GitHub serves as `refs/pull/<n>/head` and GitLab as
	/// `refs/merge-requests/<iid>/head`. The ref is fetched by itself (`origin`'s own branches are
	/// left alone) and checked out on the first of `branchCandidates` that is free, or that an
	/// earlier call made for the same ref: that one is fast-forwarded when behind and kept as is
	/// when it has commits of its own. Any other existing branch is skipped — the PR's base is an
	/// ancestor of its head too, so ancestry alone would let a fork's `main` move the local one.
	///
	/// The branch gets no upstream: the head lives in the fork, not on `origin`. Returns the folder.
	public static func createWorktree(
		fetching remoteRef: String,
		branchCandidates: [String],
		repositoryPath: String,
		worktreeBasePath: String = "../worktrees"
	) async throws -> URL {
		let fetch = await ProcessRunner.runGit(arguments: ["fetch", "origin", remoteRef], at: repositoryPath)
		guard fetch.success else {
			throw GitError.worktreeCreationFailed(fetch.trimmedError.isEmpty ? "Could not fetch \(remoteRef)." : fetch.trimmedError)
		}
		guard let head = await revision("FETCH_HEAD^{commit}", at: repositoryPath) else {
			throw GitError.worktreeCreationFailed("Could not read \(remoteRef) after fetching it.")
		}

		for branch in branchCandidates where !branch.hasPrefix("-") {
			guard let existing = await revision("refs/heads/\(branch)", at: repositoryPath) else {
				let folder = try await addWorktree(
					arguments: ["-b", branch],
					branch: branch,
					startPoint: head,
					repositoryPath: repositoryPath,
					worktreeBasePath: worktreeBasePath
				)
				_ = await ProcessRunner.runGit(
					arguments: ["config", "branch.\(branch).\(pullRequestRefKey)", remoteRef],
					at: repositoryPath
				)
				return folder
			}
			if existing == head {
				return try await addWorktree(
					arguments: [],
					branch: branch,
					startPoint: branch,
					repositoryPath: repositoryPath,
					worktreeBasePath: worktreeBasePath
				)
			}
			let marker = await ProcessRunner.runGit(
				arguments: ["config", "--get", "branch.\(branch).\(pullRequestRefKey)"],
				at: repositoryPath
			)
			guard marker.outputString.trimmingCharacters(in: .whitespacesAndNewlines) == remoteRef else {
				continue
			}
			if await isAncestor(head, of: existing, at: repositoryPath) {
				return try await addWorktree(
					arguments: [],
					branch: branch,
					startPoint: branch,
					repositoryPath: repositoryPath,
					worktreeBasePath: worktreeBasePath
				)
			}
			if await isAncestor(existing, of: head, at: repositoryPath) {
				// -B moves the branch, and refuses one checked out in another worktree.
				return try await addWorktree(
					arguments: ["-B", branch],
					branch: branch,
					startPoint: head,
					repositoryPath: repositoryPath,
					worktreeBasePath: worktreeBasePath
				)
			}
			// Diverged (the PR was force-pushed): the next candidate gets a fresh copy.
		}

		let names = branchCandidates.map { "'\($0)'" }.joined(separator: ", ")
		throw GitError.worktreeCreationFailed("Local branches \(names) already exist with other commits.")
	}

	/// Marks a branch `createWorktree(fetching:…)` made with the ref it came from, under the
	/// branch's own config section — `git branch -d/-m` drop or move it with the branch.
	static let pullRequestRefKey = "bridgeCommanderPullRequest"

	private static func addWorktree(
		arguments: [String],
		branch: String,
		startPoint: String,
		repositoryPath: String,
		worktreeBasePath: String
	) async throws -> URL {
		let folder = worktreeFolder(
			repositoryPath: repositoryPath,
			branchName: branch,
			baseBranch: "",
			createNewBranch: true,
			worktreeBasePath: worktreeBasePath
		)
		let result = await ProcessRunner.runGit(
			arguments: ["worktree", "add"] + arguments + [folder.path, startPoint],
			at: repositoryPath
		)
		guard result.success else {
			throw GitError.worktreeCreationFailed(result.trimmedError.isEmpty ? "Unknown error" : result.trimmedError)
		}
		return folder
	}

	private static func revision(_ name: String, at repositoryPath: String) async -> String? {
		let result = await ProcessRunner.runGit(arguments: ["rev-parse", "--verify", "--quiet", name], at: repositoryPath)
		let hash = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		return result.success && !hash.isEmpty ? hash : nil
	}

	private static func isAncestor(_ ancestor: String, of descendant: String, at repositoryPath: String) async -> Bool {
		await ProcessRunner.runGit(arguments: ["merge-base", "--is-ancestor", ancestor, descendant], at: repositoryPath).success
	}

	/// Adds a worktree on a new branch `branchName` that starts at `startPoint` (any revision —
	/// the graph passes a commit hash). Nothing is fetched: the start point is already local.
	///
	/// The folder is placed as `createWorktree` places it, relative to the main repository even
	/// when `repositoryPath` is itself a linked worktree, so worktrees made from either end up
	/// side by side. Returns the folder.
	public static func createWorktree(
		branchName: String,
		startPoint: String,
		repositoryPath: String,
		worktreeBasePath: String
	) async throws -> URL {
		guard !branchName.hasPrefix("-") else {
			throw GitError.worktreeCreationFailed("'\(branchName)' is not a valid branch name.")
		}

		let mainRepositoryPath = GitDirectoryResolver.resolveMainRepositoryPath(at: repositoryPath) ?? repositoryPath
		let folder = worktreeFolder(
			repositoryPath: mainRepositoryPath,
			branchName: branchName,
			baseBranch: "",
			createNewBranch: true,
			worktreeBasePath: worktreeBasePath
		)

		// `worktree add` creates the missing parent folders itself, and refuses an existing
		// non-empty folder or an existing branch with a message that says so.
		let result = await ProcessRunner.runGit(
			arguments: ["worktree", "add", "-b", branchName, folder.path, startPoint],
			at: repositoryPath
		)

		guard result.success else {
			let message = result.trimmedError
			throw GitError.worktreeCreationFailed(message.isEmpty ? "Unknown error" : message)
		}

		return folder
	}
}
