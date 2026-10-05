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

// MARK: - Ticket → branch name

public nonisolated extension BranchNameFormatter {
	/// Placeholders understood by ``branchName(ticketId:summary:template:)``.
	static let ticketPlaceholder = "{ticket}"
	static let summaryPlaceholder = "{summary}"

	/// Words first, ticket last, joined with underscores — the shape `format` reads back as the
	/// bare summary (the ticket is removed by id, the underscores become spaces).
	static let defaultTicketBranchTemplate = "{summary}_{ticket}"

	/// Longest slug a summary contributes. Ticket summaries run to whole sentences; a branch name
	/// that long is unreadable in the row and in `git branch`.
	static let maxSummarySlugLength = 50

	/// Builds a branch name for a ticket from `template`, the inverse of `format`.
	///
	/// The summary becomes a lowercase ASCII slug (diacritics folded, so Czech summaries stay
	/// readable, anything else non-alphanumeric turned into underscores). A blank template falls
	/// back to ``defaultTicketBranchTemplate``; a summary that slugs to nothing leaves no dangling
	/// separator behind.
	static func branchName(ticketId: String, summary: String, template: String) -> String {
		let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
		let pattern = trimmedTemplate.isEmpty ? defaultTicketBranchTemplate : trimmedTemplate

		var name = pattern
			.replacingOccurrences(of: ticketPlaceholder, with: ticketId)
			.replacingOccurrences(of: summaryPlaceholder, with: summarySlug(summary))

		// An empty slug leaves "_MOB-1" or "feature/_MOB-1"; collapse the separators it orphaned.
		while name.contains("__") {
			name = name.replacingOccurrences(of: "__", with: "_")
		}
		name = name
			.replacingOccurrences(of: "/_", with: "/")
			.replacingOccurrences(of: "_/", with: "/")
		return name.trimmingCharacters(in: CharacterSet(charactersIn: "_-/ "))
	}

	/// `summary` as a lowercase, underscore-separated ASCII slug of at most
	/// ``maxSummarySlugLength`` characters, cut at a word boundary.
	static func summarySlug(_ summary: String) -> String {
		let folded = summary
			.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
			.lowercased()

		var words: [String] = []
		var current = ""
		for scalar in folded.unicodeScalars {
			if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
				current.unicodeScalars.append(scalar)
			}
			else if !current.isEmpty {
				words.append(current)
				current = ""
			}
		}
		if !current.isEmpty {
			words.append(current)
		}

		var slug = ""
		for word in words {
			let candidate = slug.isEmpty ? word : slug + "_" + word
			if candidate.count > maxSummarySlugLength {
				// A single over-long first word is still better cut than dropped.
				if slug.isEmpty {
					slug = String(word.prefix(maxSummarySlugLength))
				}
				break
			}
			slug = candidate
		}
		return slug
	}
}
