import Foundation

enum GitStashHelper {
	enum StashError: Error, Equatable {
		case stashFailed(String)
		case stashPopFailed(String)
	}

	/// Stashes changes including untracked files
	/// - Parameter path: The path to the Git repository
	/// - Throws: StashError if the operation fails
	static func stash(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["stash", "-u"] // Include untracked files
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					continuation.resume()
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? "Unknown error"
					continuation.resume(throwing: StashError.stashFailed(errorMessage))
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: StashError.stashFailed(error.localizedDescription))
			}
		}
	}

	/// Pops the most recent stash
	/// - Parameter path: The path to the Git repository
	/// - Throws: StashError if the operation fails
	static func stashPop(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["stash", "pop"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					continuation.resume()
				}
				else {
					let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
					let errorMessage = String(data: errorData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? "Unknown error"
					continuation.resume(throwing: StashError.stashPopFailed(errorMessage))
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(throwing: StashError.stashPopFailed(error.localizedDescription))
			}
		}
	}

	/// Gets the current branch name
	/// - Parameter path: The path to the Git repository
	/// - Returns: The current branch name, or empty string if unable to determine
	static func getCurrentBranch(at path: String) async -> String {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["branch", "--show-current"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			process.standardOutput = outputPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let branchName = String(data: outputData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? ""
					continuation.resume(returning: branchName)
				}
				else {
					continuation.resume(returning: "")
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: "")
			}
		}
	}

	/// Checks if there is a stash on the specified branch
	/// - Parameters:
	///   - path: The path to the Git repository
	///   - branch: The branch name to check for stashes
	/// - Returns: true if a stash exists on the branch, false otherwise
	static func checkHasStashOnBranch(at path: String, branch: String) async -> Bool {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["stash", "list"]
			process.environment = GitEnvironmentHelper.setupEnvironment()

			let outputPipe = Pipe()
			process.standardOutput = outputPipe

			process.terminationHandler = { process in
				if process.terminationStatus == 0 {
					let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
					let output = String(data: outputData, encoding: .utf8)?
						.trimmingCharacters(in: .whitespacesAndNewlines)
						?? ""

					// Check if any stash entry contains the current branch
					// Format: "stash@{0}: WIP on branch-name: commit-hash commit-message"
					// or "stash@{0}: On branch-name: commit-hash commit-message"
					let hasStashOnBranch = output.split(separator: "\n").contains { line in
						line.contains("WIP on \(branch):") || line.contains("On \(branch):")
					}

					continuation.resume(returning: hasStashOnBranch)
				}
				else {
					continuation.resume(returning: false)
				}
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: false)
			}
		}
	}
}
