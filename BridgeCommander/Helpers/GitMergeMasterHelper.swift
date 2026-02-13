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
		let result = await ProcessRunner.runGit(
			arguments: ["fetch", "origin", "master"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw MergeError.fetchFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	private static func mergeOriginMaster(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["merge", "origin/master"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw MergeError.mergeFailed(
				errorMessage.isEmpty ? "Merge couldn't be finished. Check the repository state." : errorMessage
			)
		}
	}
}
