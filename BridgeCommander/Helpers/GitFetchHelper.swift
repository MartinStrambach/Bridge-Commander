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
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["fetch", "--prune", "--verbose"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					// Git fetch outputs to stderr even on success
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let output = String(data: errorData, encoding: .utf8) ?? String(
						data: outputData,
						encoding: .utf8
					) ??
						""
					let result = parseFetchOutput(output)
					continuation.resume(returning: result)
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
					guard !errorMessage.isEmpty else {
						continuation.resume(
							throwing: FetchError.fetchFailed("Fetch couldn't be finished. Check the repository state.")
						)
						return
					}

					continuation.resume(
						throwing: FetchError.fetchFailed(
							errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
						)
					)
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: error)
			}
		}
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
