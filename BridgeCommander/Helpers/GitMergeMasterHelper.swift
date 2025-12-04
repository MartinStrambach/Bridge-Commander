import Foundation

enum GitMergeMasterHelper {
	enum MergeError: Error, Equatable {
		case fetchFailed(String)
		case mergeFailed(String)
	}

	static func mergeMaster(at path: String) async throws {
		// First, fetch origin/master
		try await fetchOriginMaster(at: path)

		// Then, merge origin/master
		try await mergeOriginMaster(at: path)
	}

	private static func fetchOriginMaster(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["fetch", "origin", "master"]
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
					let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
					continuation.resume(
						throwing: MergeError.fetchFailed(
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

	private static func mergeOriginMaster(at path: String) async throws {
		try await withCheckedThrowingContinuation { continuation in
			let process = Process()
			process.currentDirectoryURL = URL(filePath: path)
			process.executableURL = URL(filePath: "/usr/bin/git")
			process.arguments = ["merge", "origin/master"]
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
					let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
					guard !errorMessage.isEmpty else {
						continuation.resume(
							throwing: MergeError.mergeFailed("Merge couldn't be finished. Check the repository state.")
						)
						return
					}

					continuation.resume(
						throwing: MergeError.mergeFailed(
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
}
