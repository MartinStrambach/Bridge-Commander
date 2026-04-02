import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Staging Client

@DependencyClient
public struct GitStagingClient: Sendable {
	public var fetchFileChanges: @Sendable (_ at: String) async -> GitFileChanges = { _ in
		GitFileChanges(staged: [], unstaged: [])
	}

	public var fetchFileDiff: @Sendable (_ at: String, _ file: FileChange, _ isStaged: Bool) async -> FileDiff?
	public var stageFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	public var unstageFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	public var stageHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	public var unstageHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	public var discardHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	public var discardFileChanges: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	public var deleteUntrackedFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	public var deleteConflictedFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	public var commit: @Sendable (_ at: String, _ message: String) async throws -> Void
}

// MARK: - File Changes Result

public struct GitFileChanges: Equatable {
	public let staged: [FileChange]
	public let unstaged: [FileChange]
	public let unpushedCount: Int

	public init(staged: [FileChange], unstaged: [FileChange], unpushedCount: Int = 0) {
		self.staged = staged
		self.unstaged = unstaged
		self.unpushedCount = unpushedCount
	}
}

// MARK: - Live Implementation

extension GitStagingClient: DependencyKey {
	public static var liveValue: GitStagingClient {
		GitStagingClient(
			fetchFileChanges: { at in
				await GitStagingHelper.fetchFileChanges(at: at)
			},
			fetchFileDiff: { at, file, isStaged in
				await GitStagingHelper.fetchFileDiff(at: at, file: file, isStaged: isStaged)
			},
			stageFiles: { at, filePaths in
				try await GitStagingHelper.stageFiles(at: at, filePaths: filePaths)
			},
			unstageFiles: { at, filePaths in
				try await GitStagingHelper.unstageFiles(at: at, filePaths: filePaths)
			},
			stageHunk: { at, file, hunk in
				try await GitStagingHelper.stageHunk(at: at, file: file, hunk: hunk)
			},
			unstageHunk: { at, file, hunk in
				try await GitStagingHelper.unstageHunk(at: at, file: file, hunk: hunk)
			},
			discardHunk: { at, file, hunk in
				try await GitStagingHelper.discardHunk(at: at, file: file, hunk: hunk)
			},
			discardFileChanges: { at, filePaths in
				try await GitStagingHelper.discardFileChanges(at: at, filePaths: filePaths)
			},
			deleteUntrackedFiles: { at, filePaths in
				try await GitStagingHelper.deleteUntrackedFiles(at: at, filePaths: filePaths)
			},
			deleteConflictedFiles: { at, filePaths in
				try await GitStagingHelper.deleteConflictedFiles(at: at, filePaths: filePaths)
			},
			commit: { at, message in
				try await GitStagingHelper.commit(at: at, message: message)
			}
		)
	}
}

extension GitStagingClient: TestDependencyKey {
	public static var testValue: GitStagingClient { GitStagingClient() }
}
