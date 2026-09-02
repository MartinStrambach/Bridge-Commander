import Foundation
import ProcessExecution

public nonisolated enum GitMergeHelper {
	public struct MergeResult: Equatable {
		public let commitsMerged: Bool
		/// The remote branch that was actually merged (without the `origin/` prefix).
		/// Callers should name this in UI rather than re-deriving it from settings,
		/// because an empty setting is auto-detected here.
		public let baseBranch: String

		public init(commitsMerged: Bool, baseBranch: String) {
			self.commitsMerged = commitsMerged
			self.baseBranch = baseBranch
		}
	}

	/// Fetches and merges `origin/<baseBranch>`. An empty `baseBranch` means
	/// "auto-detect": the remote's advertised default (`origin/HEAD`), then
	/// whichever of `origin/master` / `origin/main` exists locally.
	public static func mergeDefaultBranch(at path: String, baseBranch: String) async throws -> MergeResult {
		let branch = await GitDefaultBranchDetector.detectRemoteDefaultBranch(at: path, configured: baseBranch)

		// First, fetch origin/<branch>
		try await fetchOrigin(branch: branch, at: path)

		// Then, merge origin/<branch>
		return try await mergeOrigin(branch: branch, at: path)
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

	private static func fetchOrigin(branch: String, at path: String) async throws {
		let result = await ProcessRunner.runGit(
			arguments: ["fetch", "origin", branch],
			at: path
		)

		guard result.success else {
			let errorMessage = result.trimmedError
			throw GitError.fetchFailed(errorMessage.isEmpty ? "Unknown error" : errorMessage)
		}
	}

	private static func mergeOrigin(branch: String, at path: String) async throws -> MergeResult {
		let result = await ProcessRunner.runGit(
			arguments: ["merge", "origin/\(branch)"],
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

		return MergeResult(commitsMerged: !alreadyUpToDate, baseBranch: branch)
	}
}
