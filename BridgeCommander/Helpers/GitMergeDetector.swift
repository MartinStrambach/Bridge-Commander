import Foundation

nonisolated enum GitMergeDetector {

	/// Checks if a repository has any ongoing git operation (merge, rebase, etc.)
	/// - Parameter path: The path to the Git repository
	/// - Returns: true if any git operation is in progress, false otherwise
	static func isGitOperationInProgress(at path: String) -> Bool {
		guard let actualGitPath = GitDirectoryResolver.resolveGitDirectory(at: path) else {
			return false
		}
		return isMergeInProgress(gitPath: actualGitPath) || isRebaseInProgress(gitPath: actualGitPath)
	}

	/// Checks if a repository is currently in the middle of a rebase
	private static func isRebaseInProgress(gitPath: String) -> Bool {
		let rebaseMergePath = (gitPath as NSString).appendingPathComponent("rebase-merge")
		let rebaseApplyPath = (gitPath as NSString).appendingPathComponent("rebase-apply")
		return FileManager.default.fileExists(atPath: rebaseMergePath) ||
			FileManager.default.fileExists(atPath: rebaseApplyPath)
	}

	/// Checks if a repository is currently in the middle of a merge
	private static func isMergeInProgress(gitPath: String) -> Bool {
		let mergeHeadPath = (gitPath as NSString).appendingPathComponent("MERGE_HEAD")
		return FileManager.default.fileExists(atPath: mergeHeadPath)
	}

}
