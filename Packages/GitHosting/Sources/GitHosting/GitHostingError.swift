import Foundation

/// Thrown when a provider fetch could not complete. Distinct from a completed
/// fetch that found no PR/MR, which callers see as a `nil` result — only the
/// latter means the branch genuinely has nothing to show.
public nonisolated enum GitHostingError: Error {
	case missingToken
	case invalidURL
	case httpFailure(statusCode: Int)
}
