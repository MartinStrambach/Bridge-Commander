import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Commit Action Client

/// What the commit graph can do to a commit picked in it. Unlike `GitLogClient` and
/// `GitCommitDiffClient`, every one of these writes: it moves HEAD, adds a commit, or adds a
/// branch or worktree.
@DependencyClient
public struct GitCommitActionClient: Sendable {
	public var apply: @Sendable (
		_ operation: GitSequencerOperation,
		_ commit: GitLogCommit,
		_ at: String
	) async throws -> GitSequencerOutcome
	public var abort: @Sendable (_ operation: GitSequencerOperation, _ at: String) async throws -> Void
	public var checkoutDetached: @Sendable (_ hash: String, _ at: String) async throws -> Void
	public var checkoutBranch: @Sendable (_ branch: String, _ at: String) async throws -> Void
	public var checkoutRemoteBranch: @Sendable (_ remoteBranch: String, _ at: String) async throws -> Void
	public var createBranch: @Sendable (
		_ name: String,
		_ startPoint: String,
		_ checkout: Bool,
		_ at: String
	) async throws -> Void
	/// Returns the new worktree's folder and, when there were paths to copy, how copying went.
	public var createWorktree: @Sendable (
		_ branchName: String,
		_ startPoint: String,
		_ at: String,
		_ worktreeBasePath: String,
		_ copyPaths: [String]
	) async throws -> GitWorktreeFromCommit
}

/// A worktree added from the graph.
public struct GitWorktreeFromCommit: Equatable, Sendable {
	public let folder: URL
	public let copyResult: WorktreeFileCopier.Result?

	public init(folder: URL, copyResult: WorktreeFileCopier.Result?) {
		self.folder = folder
		self.copyResult = copyResult
	}
}

// MARK: - Live Implementation

extension GitCommitActionClient: DependencyKey {
	public static var liveValue: GitCommitActionClient {
		GitCommitActionClient(
			apply: { operation, commit, at in
				try await GitCommitActionHelper.apply(operation, commit: commit, at: at)
			},
			abort: { operation, at in
				try await GitCommitActionHelper.abort(operation, at: at)
			},
			checkoutDetached: { hash, at in
				try await GitCommitActionHelper.checkoutDetached(hash: hash, at: at)
			},
			checkoutBranch: { branch, at in
				try await GitCheckoutHelper.checkout(branch: branch, at: at)
			},
			checkoutRemoteBranch: { remoteBranch, at in
				try await GitCommitActionHelper.checkout(remoteBranch: remoteBranch, at: at)
			},
			createBranch: { name, startPoint, checkout, at in
				try await GitCommitActionHelper.createBranch(
					named: name,
					at: startPoint,
					checkout: checkout,
					repositoryPath: at
				)
			},
			createWorktree: { branchName, startPoint, at, worktreeBasePath, copyPaths in
				let folder = try await GitWorktreeCreator.createWorktree(
					branchName: branchName,
					startPoint: startPoint,
					repositoryPath: at,
					worktreeBasePath: worktreeBasePath
				)
				// Copied from the main repository, where untracked files such as local config live.
				let source = GitDirectoryResolver.resolveMainRepositoryPath(at: at) ?? at
				let copyResult: WorktreeFileCopier.Result? = copyPaths.isEmpty
					? nil
					: WorktreeFileCopier.copy(paths: copyPaths, from: URL(fileURLWithPath: source), to: folder)
				return GitWorktreeFromCommit(folder: folder, copyResult: copyResult)
			}
		)
	}
}

extension GitCommitActionClient: TestDependencyKey {
	public static var testValue: GitCommitActionClient { GitCommitActionClient() }
}
