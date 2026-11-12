import Foundation

/// Removes the bar Claude Code draws down the left of a markdown blockquote from copied text.
///
/// Claude Code renders `> quoted text` in a box whose only visible side is `▎` (its `quote` border
/// style), and wraps the quote itself, so every row on screen — continuation rows included —
/// starts with the message indent and `▎ `. Those are real cells, and a terminal copies them like
/// any other text: a quoted sentence selected across two rows came out as `…in\n  ▎ decision…`.
enum ClaudeQuoteGutter {
	/// The left side of Claude Code's `quote` border style, U+258E LEFT ONE QUARTER BLOCK.
	static let bar: Character = "\u{258E}"

	/// Strips the gutter — leading spaces, `▎` and the space after it, repeated for a nested
	/// quote — from every line that starts with one, and the padding Claude leaves at the end of
	/// such a line. Other lines, and a `▎` anywhere but the start of a line, are left as they are.
	static func strip(_ text: String) -> String {
		guard text.contains(bar) else {
			return text
		}

		return text
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map(stripLine)
			.joined(separator: "\n")
	}

	private static func stripLine(_ line: Substring) -> Substring {
		var rest = line
		var stripped = false
		while true {
			let content = rest.drop(while: { $0 == " " })
			guard content.first == bar else {
				break
			}

			rest = content.dropFirst()
			if rest.first == " " {
				rest = rest.dropFirst()
			}
			stripped = true
		}

		guard stripped else {
			return line
		}

		while rest.last == " " {
			rest = rest.dropLast()
		}

		return rest
	}
}
