import Foundation

/// Utility for resolving git directory paths, handling both regular repositories and worktrees
public nonisolated enum GitDirectoryResolver {

	/// Resolves the actual git directory path, handling both regular repos and worktrees
	/// - Parameter path: The path to the Git repository
	/// - Returns: The actual git directory path, or nil if not found
	public static func resolveGitDirectory(at path: String) -> String? {
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

	/// Resolves the git directory shared by all worktrees of a repository.
	/// For a linked worktree this is the main repository's `.git` directory;
	/// for a regular repository it is the `.git` directory itself.
	/// - Parameter path: The path to the Git repository or worktree
	/// - Returns: The common git directory path, or nil if not a git repository
	public static func resolveCommonGitDirectory(at path: String) -> String? {
		resolveGitDirectory(at: path).map(commonGitDirectory(from:))
	}

	/// Maps a per-worktree git directory (".../.git/worktrees/<name>") to the
	/// common git directory; returns any other git directory unchanged.
	static func commonGitDirectory(from gitDirectory: String) -> String {
		let components = (gitDirectory as NSString).pathComponents
		guard components.count >= 3, components[components.count - 2] == "worktrees" else {
			return gitDirectory
		}

		return NSString.path(withComponents: Array(components.dropLast(2)))
	}

	/// Checks if a directory is a Git repository or worktree
	/// - Parameter url: The directory URL to check
	/// - Returns: A tuple indicating if it's a repo and if it's a worktree
	public static func isGitRepository(at url: URL) -> (isRepo: Bool, isWorktree: Bool) {
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
	public static func isWorktree(at path: String) -> Bool {
		let expectedGitDir = (path as NSString).appendingPathComponent(".git")
		guard let resolvedGitDir = resolveGitDirectory(at: path) else {
			return false
		}

		return resolvedGitDir != expectedGitDir
	}
}
