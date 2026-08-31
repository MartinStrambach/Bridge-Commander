import Foundation
import ProcessExecution

/// Deletes the local branch a worktree had checked out after the worktree
/// itself is removed.
///
/// Git refuses to delete a branch that is still checked out in a worktree, and
/// once the worktree is removed its directory can no longer serve as a working
/// directory for git. The branch name and the main repository path therefore
/// have to be resolved while the worktree still exists, and the deletion runs
/// afterwards from the main repository.
public nonisolated enum GitLocalBranchDeleter {

	public struct ResolvedBranch: Equatable, Sendable {
		public let branchName: String
		public let mainRepositoryPath: String
	}

	/// Resolves which branch the worktree has checked out and where the main
	/// repository lives. Returns nil when there is nothing safe to delete:
	/// the worktree is on a detached HEAD (no branch), the checked-out branch
	/// is the group's default branch, or resolution itself fails.
	public static func resolveDeletableBranch(
		worktreePath: String,
		defaultBranch: String
	) async -> ResolvedBranch? {
		let branchResult = await ProcessRunner.runGit(
			arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
			at: worktreePath
		)
		let branch = branchResult.trimmedOutput
		guard branchResult.success, !branch.isEmpty else {
			return nil
		}
		guard !DefaultBranchResolver.isDefaultBranch(branch, configured: defaultBranch) else {
			return nil
		}

		let commonDirResult = await ProcessRunner.runGit(
			arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
			at: worktreePath
		)
		let commonDir = commonDirResult.trimmedOutput
		guard commonDirResult.success, !commonDir.isEmpty else {
			return nil
		}
		// --git-common-dir points at the main repository's .git directory.
		let mainRepositoryPath = URL(filePath: commonDir).deletingLastPathComponent().path

		return ResolvedBranch(branchName: branch, mainRepositoryPath: mainRepositoryPath)
	}

	/// Deletes the branch with `git branch -D`, so unmerged branches are
	/// deleted too. Git still refuses branches checked out in another worktree.
	/// - Throws: `GitError.branchDeletionFailed` when git refuses or fails.
	public static func deleteBranch(_ branch: ResolvedBranch) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["branch", "-D", branch.branchName],
			at: branch.mainRepositoryPath
		)
		guard result.success else {
			let msg = result.trimmedError
			throw GitError.branchDeletionFailed(msg.isEmpty ? "Unknown error" : msg)
		}
	}
}
