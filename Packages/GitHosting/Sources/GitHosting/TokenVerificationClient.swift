import Dependencies
import DependenciesMacros
import Foundation

/// A variable-less GraphQL query — used by the token verification calls.
nonisolated struct BareGraphQLRequest: Encodable {
	let query: String
}

/// Checks a hosting token by asking the provider who it authenticates as, over the
/// same GraphQL API the PR/MR fetches use — so a passing test means the token can
/// call that API. It does not mean every repository is reachable: an organization
/// can still refuse the token, and a fine-grained one covers a single owner.
@DependencyClient
public struct TokenVerificationClient: Sendable {
	/// Returns the GitHub login the token resolves to.
	public var verifyGitHubToken: @Sendable (_ token: String) async throws -> String
	/// Checks a token listed for a GitHub owner: whose it is, that the owner exists, and that it
	/// does not refuse the token.
	public var verifyGitHubOwnerToken: @Sendable (_ token: String, _ owner: String) async throws
		-> GitHubOwnerTokenVerification
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
		verifyGitHubOwnerToken: { token, owner in
			try await GitHubService.verifyOwnerToken(token.trimmingCharacters(in: .whitespacesAndNewlines), owner: owner)
		},
		verifyGitLabToken: { token in
			try await GitLabService.verifyToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
		}
	)
}

extension TokenVerificationClient: TestDependencyKey {
	public static let testValue = TokenVerificationClient()
}
