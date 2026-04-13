import Foundation

public nonisolated enum BranchNameFormatter {
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
		if let regex = try? NSRegularExpression(pattern: branchNameRegex, options: .caseInsensitive) {
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
		formatted = formatted
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
			.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

		return formatted
	}
}
