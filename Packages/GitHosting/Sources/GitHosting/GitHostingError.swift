import Foundation

/// Thrown when a provider fetch could not complete. Distinct from a completed
/// fetch that found no PR/MR, which callers see as a `nil` result — only the
/// latter means the branch genuinely has nothing to show.
public nonisolated enum GitHostingError: Error {
	case missingToken
	case invalidURL
	case httpFailure(statusCode: Int)
	/// The request succeeded but resolved to no authenticated user — the token was
	/// accepted at the HTTP layer yet grants no API identity (e.g. missing scope).
	case unauthenticated
}
