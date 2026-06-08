import Foundation
import Synchronization

public nonisolated enum BranchNameFormatter {
	/// Cache of compiled ticket-pattern regexes, keyed by pattern string.
	/// `format` runs in SwiftUI view bodies (per row, per redraw), so compiling
	/// `NSRegularExpression` on every call is a real scroll-time cost. Compile once per pattern.
	private static let ticketRegexCache = Mutex<[String: NSRegularExpression]>([:])

	/// Precompiled regex collapsing runs of 2+ spaces into one.
	private static let multipleSpacesRegex = try! NSRegularExpression(pattern: "  +")

	/// Returns the compiled regex for `pattern`, compiling and caching it on first use.
	/// Returns nil if the pattern is invalid (matching the previous `try?` behavior).
	private static func ticketRegex(for pattern: String) -> NSRegularExpression? {
		ticketRegexCache.withLock { cache in
			if let cached = cache[pattern] {
				return cached
			}
			guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
				return nil
			}
			cache[pattern] = regex
			return regex
		}
	}

	/// Returns a formatted, human-readable version of a branch name
	/// Removes prefixes (feature/fix/etc), project types, ticket numbers, and replaces underscores with spaces
	public static func format(_ branchName: String?, ticketId: String? = nil, branchNameRegex: String) -> String {
		guard let branchName else {
			return ""
		}

		var formatted = branchName

		// 1. Remove prefix segments (feature/, fix/, ios/, android/, etc.)
		// A segment without underscores is treated as a type/platform prefix; stop when content begins.
		while let slashIndex = formatted.firstIndex(of: "/") {
			let segment = String(formatted[..<slashIndex])
			if segment.contains("_") { break }
			formatted = String(formatted[formatted.index(after: slashIndex)...])
		}

		// 2. Remove project type patterns like "tech-60", "mob-45" (case insensitive)
		// Pattern: configurable via branchNameRegex parameter
		if let regex = ticketRegex(for: branchNameRegex) {
			let range = NSRange(formatted.startIndex..., in: formatted)
			formatted = regex.stringByReplacingMatches(
				in: formatted,
				range: range,
				withTemplate: ""
			)
		}

		// 3. Remove ticket number
		if let ticketId {
			formatted = formatted.replacingOccurrences(of: ticketId, with: "")
		}

		// 4. Replace underscores with spaces
		formatted = formatted.replacingOccurrences(of: "_", with: " ")

		// 5. Clean up: trim whitespace, remove multiple consecutive spaces, remove leading/trailing slashes
		formatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
		let spacesRange = NSRange(formatted.startIndex..., in: formatted)
		formatted = multipleSpacesRegex.stringByReplacingMatches(
			in: formatted,
			range: spacesRange,
			withTemplate: " "
		)
		formatted = formatted.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

		return formatted
	}
}
