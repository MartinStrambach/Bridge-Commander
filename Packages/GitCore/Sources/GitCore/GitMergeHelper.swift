import Foundation
import ProcessExecution

public nonisolated enum GitMergeHelper {
	public struct MergeResult: Equatable {
		public let commitsMerged: Bool

		public init(commitsMerged: Bool) {
			self.commitsMerged = commitsMerged
		}
	}

	public static func mergeMaster(at path: String) async throws -> MergeResult {
		// First, fetch origin/master
		try await fetchOriginMaster(at: path)

		// Then, merge origin/master
		return try await mergeOriginMaster(at: path)
	}

	public static func finishMerge(at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["commit", "--no-edit"],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.mergeFailed(
				errorMessage.isEmpty ? "Failed to finish merge" : errorMessage
			)
		}
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
