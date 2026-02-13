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
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["pull", "--prune"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let output = String(data: outputData, encoding: .utf8) ?? ""
					Task {
						let result = await parsePullOutput(output, at: path)
						continuation.resume(returning: result)
					}
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

	private static func parsePullOutput(_ output: String, at path: String) async -> PullResult {
		let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)

		// Check if already up to date
		if trimmedOutput.contains("Already up to date") || trimmedOutput.contains("Already up-to-date") {
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
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["rev-list", "--count", "\(from)..\(to)"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			process.standardOutput = outputPipe

			let outputCollector = PipeDataCollector()

			// Continuously read from output pipe in background to prevent buffer overflow
			outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
				let data = fileHandle.availableData
				outputCollector.append(data)
			}

			process.terminationHandler = { proc in
				// Stop reading from pipe
				outputPipe.fileHandleForReading.readabilityHandler = nil

				// Read any remaining data
				let remainingOutput = (try? outputPipe.fileHandleForReading.readToEnd()) ?? Data()
				outputCollector.append(remainingOutput)

				if proc.terminationStatus == 0 {
					let outputData = outputCollector.getData()
					let output = String(data: outputData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
					continuation.resume(returning: Int(output) ?? 0)
				}
				else {
					continuation.resume(returning: 0)
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: 0)
			}
		}
	}
}
