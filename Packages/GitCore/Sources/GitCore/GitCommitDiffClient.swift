import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Commit Diff Client

/// Read-only access to what a commit changed. Nothing here writes to the repository, so a
/// selection in the commit graph never moves HEAD, the index or the working tree.
@DependencyClient
public struct GitCommitDiffClient: Sendable {
	public var fetchFileChanges: @Sendable (_ at: String, _ commitHash: String) async -> [FileChange] = { _, _ in [] }
	public var fetchFileDiff: @Sendable (_ at: String, _ commitHash: String, _ file: FileChange) async -> FileDiff?
}

// MARK: - Live Implementation

extension GitCommitDiffClient: DependencyKey {
	public static var liveValue: GitCommitDiffClient {
		GitCommitDiffClient(
			fetchFileChanges: { at, commitHash in
				await GitCommitDiffHelper.fetchFileChanges(at: at, commitHash: commitHash)
			},
			fetchFileDiff: { at, commitHash, file in
				await GitCommitDiffHelper.fetchFileDiff(at: at, commitHash: commitHash, file: file)
			}
		)
	}
}

extension GitCommitDiffClient: TestDependencyKey {
	public static var testValue: GitCommitDiffClient { GitCommitDiffClient() }
}
