import Foundation

struct GitChanges {
	let unstagedCount: Int
	let stagedCount: Int
}

enum GitStatusDetector {

	/// Detects both staged and unstaged changes in a repository
	/// Uses `git ls-files -m` for unstaged changes and `git diff --name-only --cached` for staged changes
	/// - Parameter path: The path to the Git repository
	/// - Returns: A GitChanges struct with both counts
	static func getChangesCount(at path: String) async -> GitChanges {
		async let unstaged = getUnstagedCount(at: path)
		async let staged = getStagedCount(at: path)

		return await GitChanges(
			unstagedCount: unstaged,
			stagedCount: staged
		)
	}

	/// Counts unstaged changes using git ls-files -m
	private static func getUnstagedCount(at path: String) async -> Int {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["ls-files", "-m"]

			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = Pipe()

			process.terminationHandler = { _ in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8) ?? ""
				let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

				let result = trimmed.isEmpty ? 0 : trimmed.split(separator: "\n").count
				continuation.resume(returning: result)
			}

			do {
				try process.run()
			}
			catch {
				continuation.resume(returning: 0)
			}
		}
	}

	/// Counts staged changes using git diff --name-only --cached
	private static func getStagedCount(at path: String) async -> Int {
		await withCheckedContinuation { continuation in
			let process = Process()
			process.currentDirectoryPath = path
			process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
			process.arguments = ["diff", "--name-only", "--cached"]

			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = Pipe()

			process.terminationHandler = { _ in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8) ?? ""
				let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

				let result = trimmed.isEmpty ? 0 : trimmed.split(separator: "\n").count
				continuation.resume(returning: result)
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
