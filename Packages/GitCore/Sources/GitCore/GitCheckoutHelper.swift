import Foundation
import ProcessExecution

public nonisolated enum GitCheckoutHelper {
	/// Switches the working tree to the repository's default branch and returns the
	/// branch name that was actually checked out. An empty `baseBranch` means
	/// "auto-detect" (see `GitDefaultBranchDetector.detectDefaultBranch`).
	///
	/// Plain `git checkout <branch>` is enough for both the local and the remote-only
	/// case: when only `origin/<branch>` exists, git creates a local tracking branch
	/// of the same name. Nothing is fetched first — this is meant to be a quick local
	/// switch; pulling the branch up to date is a separate action.
	public static func checkoutDefaultBranch(at path: String, baseBranch: String) async throws -> String {
		let branch = await GitDefaultBranchDetector.detectDefaultBranch(at: path, configured: baseBranch)
		try await checkout(branch: branch, at: path)
		return branch
	}

	public static func checkout(branch: String, at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["checkout", branch],
			at: path
		)

		guard result.success else {
			throw GitError.checkoutFailed(describeFailure(branch: branch, stderr: result.trimmedError))
		}
	}

	/// Turns git's pathspec complaint (what it says when neither `<branch>` nor
	/// `origin/<branch>` exists) into something that names the actual problem.
	static func describeFailure(branch: String, stderr: String) -> String {
		if stderr.contains("did not match any file(s) known to git") {
			return "Branch '\(branch)' was not found locally or on origin."
		}
		return stderr.isEmpty ? "Checkout couldn't be finished. Check the repository state." : stderr
	}
}
