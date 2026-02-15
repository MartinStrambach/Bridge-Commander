import Foundation

nonisolated enum GitMergeDetector {

	/// Checks if a repository has any ongoing git operation (merge, rebase, etc.)
	/// - Parameter path: The path to the Git repository
	/// - Returns: true if any git operation is in progress, false otherwise
	static func isGitOperationInProgress(at path: String) -> Bool {
		isMergeInProgress(at: path) || isRebaseInProgress(at: path)
	}

	/// Checks if a repository is currently in the middle of a rebase
	/// - Parameter path: The path to the Git repository
	/// - Returns: true if rebase is in progress, false otherwise
	private static func isRebaseInProgress(at path: String) -> Bool {
		guard let actualGitPath = GitDirectoryResolver.resolveGitDirectory(at: path) else {
			return false
		}

		// Check for rebase-merge or rebase-apply directories
		let rebaseMergePath = (actualGitPath as NSString).appendingPathComponent("rebase-merge")
		let rebaseApplyPath = (actualGitPath as NSString).appendingPathComponent("rebase-apply")

		return FileManager.default.fileExists(atPath: rebaseMergePath) ||
			FileManager.default.fileExists(atPath: rebaseApplyPath)
	}

	/// Checks if a repository is currently in the middle of a merge
	/// - Parameter path: The path to the Git repository
	/// - Returns: true if merge is in progress, false otherwise
	private static func isMergeInProgress(at path: String) -> Bool {
		guard let actualGitPath = GitDirectoryResolver.resolveGitDirectory(at: path) else {
			return false
		}

		// Check if MERGE_HEAD file exists - this indicates an ongoing merge
		let mergeHeadPath = (actualGitPath as NSString).appendingPathComponent("MERGE_HEAD")
		return FileManager.default.fileExists(atPath: mergeHeadPath)
	}

}
