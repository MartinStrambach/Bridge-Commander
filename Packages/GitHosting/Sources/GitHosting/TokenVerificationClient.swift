import Dependencies
import DependenciesMacros
import Foundation

/// A variable-less GraphQL query — used by the token verification calls.
nonisolated struct BareGraphQLRequest: Encodable {
	let query: String
}

/// Checks a hosting token by asking the provider who it authenticates as, over the
/// same GraphQL API the PR/MR fetches use — so a passing test means those fetches
/// will actually work, scopes included.
@DependencyClient
public struct TokenVerificationClient: Sendable {
	/// Returns the GitHub login the token resolves to.
	public var verifyGitHubToken: @Sendable (_ token: String) async throws -> String
	/// Returns the GitLab username the token resolves to.
	public var verifyGitLabToken: @Sendable (_ token: String) async throws -> String
}

extension TokenVerificationClient: DependencyKey {
	public static let liveValue = TokenVerificationClient(
		// Trimmed for the same reason as the fetch path: tokens saved before
		// Settings started trimming may still carry pasted whitespace.
		verifyGitHubToken: { token in
			try await GitHubService.verifyToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
		},
		verifyGitLabToken: { token in
			try await GitLabService.verifyToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
		}
	)
}

extension TokenVerificationClient: TestDependencyKey {
	public static let testValue = TokenVerificationClient()
}
