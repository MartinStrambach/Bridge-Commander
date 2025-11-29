import Foundation

enum BranchNameFormatter {
	/// Returns a formatted, human-readable version of a branch name
	/// Removes prefixes (feature/fix/etc), project types, ticket numbers, and replaces underscores with spaces
	static func format(_ branchName: String?, ticketId: String? = nil) -> String {
		guard let branchName else {
			return ""
		}

		var formatted = branchName

		// 1. Remove part before first slash (feature, fix, bugfix, etc.)
		if let firstSlashIndex = formatted.firstIndex(of: "/") {
			formatted = String(formatted[formatted.index(after: firstSlashIndex)...])
		}

		// 2. Remove project type patterns like "tech-60", "mob-45" (case insensitive)
		// Pattern: word-digits followed by underscore or slash
		let projectTypePattern = "[a-zA-Z]+-\\d+[_/]"
		if let regex = try? NSRegularExpression(pattern: projectTypePattern, options: .caseInsensitive) {
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
