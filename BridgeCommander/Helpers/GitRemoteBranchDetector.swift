import Foundation

nonisolated enum GitRemoteBranchDetector {
	/// Checks if the current branch has a remote tracking branch
	static func hasRemoteBranch(at path: String) async -> Bool {
		let result = await ProcessRunner.runGit(
			arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
			at: path
		)

		guard result.success else {
			return false
		}

		let output = result.trimmedOutput
		return !output.isEmpty
	}
}
