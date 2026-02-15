import Foundation

nonisolated enum GitMergeMasterHelper {
	struct MergeResult: Equatable {
		let commitsMerged: Bool
	}

	static func mergeMaster(at path: String) async throws -> MergeResult {
		// First, fetch origin/master
		try await fetchOriginMaster(at: path)

		// Then, merge origin/master
		return try await mergeOriginMaster(at: path)
	}

	private static func fetchOriginMaster(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["fetch", "origin", "master"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.fetchFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	private static func mergeOriginMaster(at path: String) async throws -> MergeResult {
		let result = await ProcessRunner.runGit(
			arguments: ["merge", "origin/master"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.mergeFailed(
				errorMessage.isEmpty ? "Merge couldn't be finished. Check the repository state." : errorMessage
			)
		}

		// Check if the output indicates no commits were merged
		let output = result.trimmedOutput
		let alreadyUpToDate = output.isAlreadyUpToDate

		return MergeResult(commitsMerged: !alreadyUpToDate)
	}
}
