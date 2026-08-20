import Foundation
import Synchronization

public nonisolated enum GitBranchDetector {

	/// Cache of compiled ticket-pattern regexes, keyed by pattern string.
	/// `extractTicketId` runs for every row when it is built, on every status refresh, and again
	/// whenever group settings change — all against a handful of distinct patterns, so compiling
	/// `NSRegularExpression` per call is pure repeat work. (Same reasoning as
	/// `BranchNameFormatter.ticketRegexCache`.)
	private static let ticketRegexCache = Mutex<[String: NSRegularExpression]>([:])

	/// Returns the compiled regex for `pattern`, compiling and caching it on first use.
	/// Returns nil if the pattern is invalid (matching the previous `try?` behavior).
	private static func ticketRegex(for pattern: String) -> NSRegularExpression? {
		ticketRegexCache.withLock { cache in
			if let cached = cache[pattern] {
				return cached
			}
			guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
				return nil
			}
			cache[pattern] = regex
			return regex
		}
	}

	/// Extracts a ticket ID from a branch name using a regex pattern
	/// - Parameters:
	///   - branchName: The Git branch name
	///   - pattern: The regex pattern to use for extraction (e.g., "MOB-[0-9]+")
	/// - Returns: The ticket ID (e.g., "MOB-1963"), or nil if not found
	public static func extractTicketId(from branchName: String, pattern: String) -> String? {
		guard let regex = ticketRegex(for: pattern) else {
			return nil
		}

		let range = NSRange(branchName.startIndex..., in: branchName)
		guard let match = regex.firstMatch(in: branchName, options: [], range: range) else {
			return nil
		}
		guard let matchRange = Range(match.range, in: branchName) else {
			return nil
		}

		let ticketId = String(branchName[matchRange])
		return ticketId
	}

}
