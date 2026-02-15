import Foundation

nonisolated enum GitDetector {

	/// Checks if a directory is a Git repository or worktree
	/// - Parameter url: The directory URL to check
	/// - Returns: A tuple indicating if it's a repo and if it's a worktree
	static func isGitRepository(at url: URL) -> (isRepo: Bool, isWorktree: Bool) {
		// Use shared resolver to check if git directory exists
		guard GitDirectoryResolver.resolveGitDirectory(at: url.path) != nil else {
			return (false, false)
		}

		// Check if it's a worktree
		let isWorktree = GitDirectoryResolver.isWorktree(at: url.path)
		return (true, isWorktree)
	}

	/// Recursively scans a directory for Git repositories
	/// - Parameter rootURL: The root directory to scan
	/// - Returns: An array of discovered repositories (without status counts)
	static func scanForRepositories(at rootURL: URL) async -> [ScannedRepository] {
		var repositories: [ScannedRepository] = []
		var visitedPaths: Set<String> = []

		await scanDirectory(
			url: rootURL,
			repositories: &repositories,
			visitedPaths: &visitedPaths,
		)

		return repositories.sorted { $0.path < $1.path }
	}

	/// Recursively scans a single directory
	private static func scanDirectory(
		url: URL,
		repositories: inout [ScannedRepository],
		visitedPaths: inout Set<String>,
	) async {
		// Avoid scanning the same path twice (handles symlinks)
		let canonicalPath = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? url.path
		guard !visitedPaths.contains(canonicalPath) else {
			return
		}

		visitedPaths.insert(canonicalPath)

		// Check if this directory is a Git repository
		let (isRepo, isWorktree) = isGitRepository(at: url)

		if isRepo {
			let repoName = url.lastPathComponent
			let branchName = GitBranchDetector.getCurrentBranch(at: url.path)
			let mergeInProgress = GitMergeDetector.isGitOperationInProgress(at: url.path)

			let repo = ScannedRepository(
				path: url.path,
				name: repoName,
				directory: url.deletingLastPathComponent().path,
				isWorktree: isWorktree,
				branchName: branchName,
				isMergeInProgress: mergeInProgress,
			)
			repositories.append(repo)
			return
		}

		// Get directory contents in a synchronous context
		let subdirectories = getNonMainRepositorySubdirectories(at: url)

		// Recursively scan subdirectories
		for subdir in subdirectories {
			await scanDirectory(
				url: subdir,
				repositories: &repositories,
				visitedPaths: &visitedPaths,
			)
		}
	}

	/// Gets all subdirectories that aren't repositories themselves
	private static func getNonMainRepositorySubdirectories(at url: URL) -> [URL] {
		guard
			let enumerator = FileManager.default.enumerator(
				at: url,
				includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
				options: [.skipsPackageDescendants]
			)
		else {
			return []
		}

		var subdirectories: [URL] = []

		for case let fileURL as URL in enumerator {
			// Skip hidden files and directories except .git
			let fileName = fileURL.lastPathComponent
			if fileName.hasPrefix("."), fileName != ".git" {
				enumerator.skipDescendants()
				continue
			}

			// Check if it's a directory
			guard
				let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
				let isDirectory = resourceValues.isDirectory,
				isDirectory
			else {
				continue
			}

			// Skip .git directories to avoid scanning inside them
			if fileName == ".git" {
				enumerator.skipDescendants()
				continue
			}

			// Skip common non-repo directories for performance
			let skipDirs = ["node_modules", "target", "build", "dist", ".idea", ".vscode"]
			if skipDirs.contains(fileName) {
				enumerator.skipDescendants()
				continue
			}

			// Skip descendant processing since we'll handle subdirectories separately
			enumerator.skipDescendants()
			subdirectories.append(fileURL)
		}

		return subdirectories
	}
}
