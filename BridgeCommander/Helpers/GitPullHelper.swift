import Foundation

enum GitPullHelper {
	struct PullResult: Equatable {
		let commitCount: Int
		let isAlreadyUpToDate: Bool
	}

	enum PullError: Error, Equatable {
		case pullFailed(String)
	}

	static func pull(at path: String) async throws -> PullResult {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["pull"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let output = String(data: outputData, encoding: .utf8) ?? ""
					let result = parsePullOutput(output)
					continuation.resume(returning: result)
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
					guard !errorMessage.isEmpty else {
						continuation.resume(
							throwing: PullError.pullFailed("Pull couldn't be finished. Check the repository state.")
						)
						return
					}

					continuation.resume(
						throwing: PullError.pullFailed(
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

	private static func parsePullOutput(_ output: String) -> PullResult {
		let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

		// Check if already up to date
		if trimmedOutput.contains("Already up to date") || trimmedOutput.contains("Already up-to-date") {
			return PullResult(commitCount: 0, isAlreadyUpToDate: true)
		}

		// Try to extract commit count from output
		// Look for patterns like "Updating abc123..def456" or "Fast-forward"
		var commitCount = 0

		// Count insertions/deletions lines as indicator of changes
		let lines = trimmedOutput.components(separatedBy: .newlines)
		for line in lines {
			// Look for commit hash references or file changes
			if line.contains("file changed") || line.contains("files changed") {
				// Extract number before "file(s) changed"
				if let match = line.range(of: #"\d+"#, options: .regularExpression) {
					let numberStr = String(line[match])
					if let fileCount = Int(numberStr), fileCount > 0 {
						// Estimate at least 1 commit if files changed
						commitCount = max(1, commitCount)
					}
				}
			}
			else if line.contains("Fast-forward") {
				// Fast-forward indicates at least 1 commit
				commitCount = max(1, commitCount)
			}
		}

		// If we see update references, count the commits
		if let updateRange = trimmedOutput.range(of: #"Updating [0-9a-f]+\.\.[0-9a-f]+"#, options: .regularExpression) {
			let updateLine = String(trimmedOutput[updateRange])
			// Extract the commit range and count
			if let dotDotRange = updateLine.range(of: "..") {
				commitCount = max(1, commitCount) // At least 1 commit
			}
		}

		return PullResult(commitCount: commitCount, isAlreadyUpToDate: false)
	}
}
