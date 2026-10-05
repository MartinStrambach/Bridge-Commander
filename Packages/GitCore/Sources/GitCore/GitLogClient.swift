import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Git Log Client

/// Read-only access to the commit history the graph draws.
@DependencyClient
public struct GitLogClient: Sendable {
	public var loadCommits: @Sendable (_ at: String, _ limit: Int, _ search: GitLogSearch?) async throws -> [GitLogCommit]
}

// MARK: - Live Implementation

extension GitLogClient: DependencyKey {
	public static var liveValue: GitLogClient {
		GitLogClient(
			loadCommits: { at, limit, search in
				try await GitLogHelper.loadCommits(at: at, limit: limit, search: search)
			}
		)
	}
}

extension GitLogClient: TestDependencyKey {
	public static var testValue: GitLogClient { GitLogClient() }
}
