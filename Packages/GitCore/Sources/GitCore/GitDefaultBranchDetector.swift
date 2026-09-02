import Foundation
import ProcessExecution

/// Resolves which `origin/<branch>` counts as the repository's default branch,
/// for callers that need a concrete remote branch name (e.g. "merge default branch").
///
/// The decision itself lives in `DefaultBranchResolver.resolveRemoteDefaultBranch`;
/// this type only gathers the git facts it needs. Nothing here touches the network:
/// `origin/HEAD` and the remote-tracking refs are read from the local git directory,
/// which every worktree of a repository shares.
public nonisolated enum GitDefaultBranchDetector {

	/// Returns the remote branch to merge from. A non-empty `configured` value is
	/// returned as-is without spawning any git process.
	public static func detectRemoteDefaultBranch(at path: String, configured: String) async -> String {
		let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.isEmpty else {
			return trimmed
		}

		let originHead = await originHeadBranch(at: path)
		// Skip listing refs when origin/HEAD already answers the question.
		let remoteBranches = originHead == nil ? await remoteBranchNames(at: path) : []

		return DefaultBranchResolver.resolveRemoteDefaultBranch(
			configured: trimmed,
			originHead: originHead,
			remoteBranches: remoteBranches
		)
	}

	/// Returns the branch name to check out as the default branch. Unlike
	/// `detectRemoteDefaultBranch`, local-only branches count as candidates too, so a
	/// repository without a remote still resolves to whichever of master/main it has.
	/// A non-empty `configured` value is returned as-is without spawning any git process.
	public static func detectDefaultBranch(at path: String, configured: String) async -> String {
		let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.isEmpty else {
			return trimmed
		}

		let originHead = await originHeadBranch(at: path)
		let candidates = originHead == nil
			? await GitBranchListHelper.listBranchesWithInfo(at: path).map(\.name)
			: []

		return DefaultBranchResolver.resolveDefaultBranch(
			configured: trimmed,
			originHead: originHead,
			candidates: candidates
		)
	}

	/// `origin/HEAD` as a short ref (e.g. "origin/main"), or nil when the remote's
	/// default branch has never been recorded locally (repos that were `git init`ed
	/// and had a remote added by hand, rather than cloned).
	private static func originHeadBranch(at path: String) async -> String? {
		let result = await ProcessRunner.runGit(
			arguments: ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
			at: path
		)
		let ref = result.trimmedOutput
		guard result.success, !ref.isEmpty else {
			return nil
		}
		return ref
	}

	private static func remoteBranchNames(at path: String) async -> [String] {
		await GitBranchListHelper.listBranchesWithInfo(at: path)
			.filter(\.existsRemotely)
			.map(\.name)
	}
}
