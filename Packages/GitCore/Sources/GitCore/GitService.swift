import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Service

@DependencyClient
public struct GitClient: Sendable {
	public var getCurrentBranch: @Sendable (_ at: String) async -> GitPorcelainStatus = { _ in
		GitPorcelainStatus(parsing: "")
	}

	public var mergeMaster: @Sendable (_ at: String) async throws -> GitMergeHelper.MergeResult
	public var pull: @Sendable (_ at: String) async throws -> GitPullHelper.PullResult
	public var fetch: @Sendable (_ at: String) async throws -> GitFetchHelper.FetchResult
}

extension GitClient: DependencyKey {
	public static var liveValue: GitClient {
		GitClient(
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
}

extension GitClient: TestDependencyKey {
	public static var testValue: GitClient { GitClient() }
}
