import Foundation

nonisolated enum GitBranchDetector {

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
