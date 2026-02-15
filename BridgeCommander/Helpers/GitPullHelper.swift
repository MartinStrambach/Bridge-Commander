import Foundation

nonisolated enum GitPullHelper {
	struct PullResult: Equatable {
		let commitCount: Int
		let isAlreadyUpToDate: Bool
	}

	static func pull(at path: String) async throws -> PullResult {
		let result = await ProcessRunner.runGit(
			arguments: ["pull", "--prune"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.pullFailed(
				errorMessage.isEmpty ? "Pull couldn't be finished. Check the repository state." : errorMessage
			)
		}

		return await parsePullOutput(result.outputString, at: path)
	}

	private static func parsePullOutput(_ output: String, at path: String) async -> PullResult {
		let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

		// Check if already up to date
		if trimmedOutput.isAlreadyUpToDate {
			return PullResult(commitCount: 0, isAlreadyUpToDate: true)
		}

		// Try to extract commit range from output
		// Look for patterns like "Updating abc123..def456"
		var commitCount = 0

		// Extract commit range from "Updating" line
		if let updateRange = trimmedOutput.range(of: #"Updating [0-9a-f]+\.\.[0-9a-f]+"#, options: .regularExpression) {
			let updateLine = String(trimmedOutput[updateRange])
			// Extract the two commit hashes
			let pattern = #"Updating ([0-9a-f]+)\.\.([0-9a-f]+)"#
			if
				let regex = try? NSRegularExpression(pattern: pattern),
				let match = regex.firstMatch(in: updateLine, range: NSRange(updateLine.startIndex..., in: updateLine)),
				match.numberOfRanges == 3,
				let fromRange = Range(match.range(at: 1), in: updateLine),
				let toRange = Range(match.range(at: 2), in: updateLine)
			{
				let fromHash = String(updateLine[fromRange])
				let toHash = String(updateLine[toRange])

				// Count commits between the two hashes
				// The range is exclusive of the first commit, so we count from..to
				commitCount = await countCommitsBetween(from: fromHash, to: toHash, at: path)
			}
		}

		// Fallback: if we couldn't parse the commit range but see changes, estimate 1 commit
		if
			commitCount == 0,
			trimmedOutput.contains("Fast-forward") || trimmedOutput.contains("file changed") || trimmedOutput
				.contains("files changed")
		{
			commitCount = 1
		}

		return PullResult(commitCount: commitCount, isAlreadyUpToDate: false)
	}

	private static func countCommitsBetween(from: String, to: String, at path: String) async -> Int {
		let result = await ProcessRunner.runGit(
			arguments: ["rev-list", "--count", "\(from)..\(to)"],
			at: path
		)

		guard result.success else {
			return 0
		}

		let output = result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
		return Int(output) ?? 0
	}
}
