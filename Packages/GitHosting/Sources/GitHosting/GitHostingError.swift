import Foundation

/// Thrown when a provider fetch could not complete. Distinct from a completed
/// fetch that found no PR/MR, which callers see as a `nil` result — only the
/// latter means the branch genuinely has nothing to show.
public nonisolated enum GitHostingError: Error {
	case missingToken
	case invalidURL
	case httpFailure(statusCode: Int)
	/// The request succeeded but did not resolve to the requested identity or
	/// resource — the token was accepted at the HTTP layer yet grants no access
	/// (missing scope, no membership, or a fine-grained token's GraphQL gaps).
	case unauthenticated
}
