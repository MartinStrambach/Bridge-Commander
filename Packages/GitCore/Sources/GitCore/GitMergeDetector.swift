import Foundation

public nonisolated enum GitMergeDetector {

	/// Checks if a repository has any ongoing git operation (merge, rebase, etc.)
	/// - Parameter path: The path to the Git repository
	/// - Returns: true if any git operation is in progress, false otherwise
	public static func isGitOperationInProgress(at path: String) -> Bool {
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

	/// The branch a rebase under way is rebasing, which git records in `head-name` while HEAD is
	/// detached. Nil when no rebase is under way, or when it started from a detached HEAD.
	public static func branchBeingRebased(at path: String) -> String? {
		guard let gitPath = GitDirectoryResolver.resolveGitDirectory(at: path) else {
			return nil
		}

		for directory in ["rebase-merge", "rebase-apply"] {
			let headNamePath = (gitPath as NSString).appendingPathComponent("\(directory)/head-name")
			guard let contents = try? String(contentsOfFile: headNamePath, encoding: .utf8) else {
				continue
			}

			let ref = contents.trimmingCharacters(in: .whitespacesAndNewlines)
			let headsPrefix = "refs/heads/"
			return ref.hasPrefix(headsPrefix) ? String(ref.dropFirst(headsPrefix.count)) : nil
		}
		return nil
	}

	/// Checks if a repository is currently in the middle of a merge
	private static func isMergeInProgress(gitPath: String) -> Bool {
		let mergeHeadPath = (gitPath as NSString).appendingPathComponent("MERGE_HEAD")
		return FileManager.default.fileExists(atPath: mergeHeadPath)
	}

}
