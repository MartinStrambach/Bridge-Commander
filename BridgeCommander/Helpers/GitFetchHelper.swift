import Foundation

enum GitFetchHelper {
	struct FetchResult: Equatable {
		let fetchedBranches: Int
		let isAlreadyUpToDate: Bool
	}

	enum FetchError: Error, Equatable {
		case fetchFailed(String)
	}

	static func fetch(at path: String) async throws -> FetchResult {
		let result = await ProcessRunner.runGit(
			arguments: ["fetch", "--prune", "--verbose"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw FetchError.fetchFailed(
				errorMessage.isEmpty ? "Fetch couldn't be finished. Check the repository state." : errorMessage
			)
		}

		// Git fetch outputs to stderr even on success
		let output = result.errorString.isEmpty ? result.outputString : result.errorString
		return parseFetchOutput(output)
	}

	private static func parseFetchOutput(_ output: String) -> FetchResult {
		let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

		// If output is empty or minimal, nothing was fetched
		if trimmedOutput.isEmpty || trimmedOutput.count < 10 {
			return FetchResult(fetchedBranches: 0, isAlreadyUpToDate: true)
		}

		// Count lines that indicate branch updates (lines with -> in them)
		let lines = trimmedOutput.components(separatedBy: .newlines)
		var branchCount = 0

		for line in lines {
			// Look for patterns like:
			// - "abc123..def456  branch-name -> origin/branch-name" (updated)
			// - "* [new branch]      branch-name -> origin/branch-name" (new)
			// - " - [deleted]         (none)     -> origin/branch-name" (pruned)
			if line.contains("->") {
				if line.contains("..") || line.contains("[new") || line.contains("[deleted]") {
					branchCount += 1
				}
			}
		}

		let isAlreadyUpToDate = branchCount == 0
		return FetchResult(fetchedBranches: branchCount, isAlreadyUpToDate: isAlreadyUpToDate)
	}
}
