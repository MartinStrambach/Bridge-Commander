import Foundation

/// Utility for resolving git directory paths, handling both regular repositories and worktrees
nonisolated enum GitDirectoryResolver {

	/// Resolves the actual git directory path, handling both regular repos and worktrees
	/// - Parameter path: The path to the Git repository
	/// - Returns: The actual git directory path, or nil if not found
	static func resolveGitDirectory(at path: String) -> String? {
		let gitPath = (path as NSString).appendingPathComponent(".git")
		var isDirectory: ObjCBool = false
		let gitExists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

		guard gitExists else {
			return nil
		}

		// If .git is a directory (regular repository), return it
		if isDirectory.boolValue {
			return gitPath
		}

		// If .git is a file (worktree), read it to find the actual git directory
		guard let gitFileContent = try? String(contentsOfFile: gitPath, encoding: .utf8) else {
			return nil
		}

		let trimmed = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("gitdir:") {
			return trimmed.replacingOccurrences(of: "gitdir:", with: "")
				.trimmingCharacters(in: .whitespaces)
		}

		return nil
	}

	/// Checks if a directory is a Git repository or worktree
	/// - Parameter url: The directory URL to check
	/// - Returns: A tuple indicating if it's a repo and if it's a worktree
	static func isGitRepository(at url: URL) -> (isRepo: Bool, isWorktree: Bool) {
		let expectedGitDir = (url.path as NSString).appendingPathComponent(".git")
		guard let resolvedGitDir = resolveGitDirectory(at: url.path) else {
			return (false, false)
		}

		// If the resolved git dir differs from the canonical .git directory path, it followed
		// a gitdir: pointer — meaning this is a worktree, not a regular repository.
		let worktree = resolvedGitDir != expectedGitDir
		return (true, worktree)
	}

	/// Checks if a path points to a git worktree (as opposed to a regular repository)
	/// - Parameter path: The path to check
	/// - Returns: true if it's a worktree, false otherwise
	static func isWorktree(at path: String) -> Bool {
		let expectedGitDir = (path as NSString).appendingPathComponent(".git")
		guard let resolvedGitDir = resolveGitDirectory(at: path) else {
			return false
		}

		return resolvedGitDir != expectedGitDir
	}
}
