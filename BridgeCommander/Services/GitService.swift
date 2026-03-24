import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Service

@DependencyClient
nonisolated struct GitClient: Sendable {
	var getCurrentBranch: @Sendable (_ at: String) async -> GitPorcelainStatus = { _ in GitPorcelainStatus(parsing: "") }
	var mergeMaster: @Sendable (_ at: String) async throws -> GitMergeHelper.MergeResult
	var pull: @Sendable (_ at: String) async throws -> GitPullHelper.PullResult
	var fetch: @Sendable (_ at: String) async throws -> GitFetchHelper.FetchResult
}

extension GitClient: DependencyKey {
	static let liveValue = GitClient(
		getCurrentBranch: { at in
			await GitStatusDetector.getStatus(at: at)
		},
		mergeMaster: { at in
			try await GitMergeHelper.mergeMaster(at: at)
		},
		pull: { at in
			try await GitPullHelper.pull(at: at)
		},
		fetch: { at in
			try await GitFetchHelper.fetch(at: at)
		}
	)
}

extension GitClient: TestDependencyKey {
	static let testValue = GitClient()
}
