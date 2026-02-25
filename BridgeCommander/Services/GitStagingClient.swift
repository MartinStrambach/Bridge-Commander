import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Staging Client

@DependencyClient
nonisolated struct GitStagingClient: Sendable {
	var fetchFileChanges: @Sendable (_ at: String) async -> GitFileChanges = { _ in
		GitFileChanges(staged: [], unstaged: [])
	}

	var fetchFileDiff: @Sendable (_ at: String, _ file: FileChange, _ isStaged: Bool) async -> FileDiff?
	var stageFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	var unstageFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	var stageHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	var unstageHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	var discardHunk: @Sendable (_ at: String, _ file: FileChange, _ hunk: DiffHunk) async throws -> Void
	var discardFileChanges: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	var deleteUntrackedFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
	var deleteConflictedFiles: @Sendable (_ at: String, _ filePaths: [String]) async throws -> Void
}

// MARK: - File Changes Result

struct GitFileChanges: Equatable, Sendable {
	let staged: [FileChange]
	let unstaged: [FileChange]
}

// MARK: - Live Implementation

extension GitStagingClient: DependencyKey {
	static let liveValue = GitStagingClient(
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
		}
	)
}

extension GitStagingClient: TestDependencyKey {
	static let testValue = GitStagingClient()
}
