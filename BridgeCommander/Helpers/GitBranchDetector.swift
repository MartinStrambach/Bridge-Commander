import Foundation

enum GitBranchDetector {

	/// Gets the current branch name for a Git repository
	/// - Parameter path: The path to the Git repository
	/// - Returns: The current branch name, or nil if not available
	static func getCurrentBranch(at path: String) -> String? {
		// Try reading .git/HEAD directly instead of using git command
		// This avoids sandbox issues with executing external processes
		let gitHeadPath = (path as NSString).appendingPathComponent(".git/HEAD")

		// Check if .git is a directory or a file (worktree)
		let gitPath = (path as NSString).appendingPathComponent(".git")
		var isDirectory: ObjCBool = false
		let gitExists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory)

		guard gitExists else {
			print("No .git found at \(path)")
			return nil
		}

		// If .git is a file (worktree), read it to find the actual git directory
		let actualGitHeadPath: String
		if !isDirectory.boolValue {
			// It's a worktree - read the .git file to find gitdir
			guard let gitFileContent = try? String(contentsOfFile: gitPath, encoding: .utf8) else {
				print("Failed to read .git file at \(path)")
				return nil
			}

			// Parse "gitdir: /path/to/git/worktrees/name"
			let trimmed = gitFileContent.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.hasPrefix("gitdir:") {
				let gitDir = trimmed.replacingOccurrences(of: "gitdir:", with: "")
					.trimmingCharacters(in: .whitespaces)
				actualGitHeadPath = (gitDir as NSString).appendingPathComponent("HEAD")
			}
			else {
				print("Invalid .git file format at \(path)")
				return nil
			}
		}
		else {
			// Regular repository
			actualGitHeadPath = gitHeadPath
		}

		// Read the HEAD file
		guard let headContent = try? String(contentsOfFile: actualGitHeadPath, encoding: .utf8) else {
			print("Failed to read HEAD file at \(actualGitHeadPath)")
			return nil
		}

		let trimmed = headContent.trimmingCharacters(in: .whitespacesAndNewlines)

		// Parse "ref: refs/heads/branch-name" or just a commit hash
		if trimmed.hasPrefix("ref:") {
			let refPath = trimmed.replacingOccurrences(of: "ref:", with: "")
				.trimmingCharacters(in: .whitespaces)

			// Extract branch name from refs/heads/branch-name
			if refPath.hasPrefix("refs/heads/") {
				let branchName = refPath.replacingOccurrences(of: "refs/heads/", with: "")
				print("Detected branch '\(branchName)' for \(path)")
				return branchName
			}
		}

		// If it's a detached HEAD (just a commit hash), return nil
		print("Repository at \(path) is in detached HEAD state")
		return nil
	}

	/// Extracts a ticket ID from a branch name using a regex pattern
	/// - Parameters:
	///   - branchName: The Git branch name
	///   - pattern: The regex pattern to use for extraction (e.g., "MOB-[0-9]+")
	/// - Returns: The ticket ID (e.g., "MOB-1963"), or nil if not found
	static func extractTicketId(from branchName: String, pattern: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
			print("Failed to create regex for ticket extraction with pattern: \(pattern)")
			return nil
		}

		let range = NSRange(branchName.startIndex..., in: branchName)
		guard let match = regex.firstMatch(in: branchName, options: [], range: range) else {
			print("No ticket ID found in branch '\(branchName)' using pattern '\(pattern)'")
			return nil
		}
		guard let matchRange = Range(match.range, in: branchName) else {
			return nil
		}

		let ticketId = String(branchName[matchRange])
		print("Extracted ticket ID '\(ticketId)' from branch '\(branchName)' using pattern '\(pattern)'")
		return ticketId
	}

	/// Counts the number of unpushed commits in a repository
	/// - Parameter path: The path to the Git repository
	/// - Returns: The number of unpushed commits, or 0 if no upstream branch or error occurs
	static func countUnpushedCommits(at path: String) async -> Int {
		let result = await ProcessRunner.runGit(
			arguments: ["rev-list", "--count", "@{u}..HEAD"],
			at: path
		)

		guard result.success else {
			return 0
		}

		let output = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		if let count = Int(output), count > 0 {
			print("Repository at \(path) has \(count) unpushed commits")
			return count
		}

		return 0
	}

	/// Counts the number of commits behind the remote branch
	/// - Parameter path: The path to the Git repository
	/// - Returns: The number of commits to pull, or 0 if no upstream branch or error occurs
	static func countCommitsBehind(at path: String) async -> Int {
		let result = await ProcessRunner.runGit(
			arguments: ["rev-list", "--count", "HEAD..@{u}"],
			at: path
		)

		guard result.success else {
			return 0
		}

		let output = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		if let count = Int(output), count > 0 {
			print("Repository at \(path) is behind by \(count) commits")
			return count
		}

		return 0
	}
}
