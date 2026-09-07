import Foundation

/// Turns raw unified-diff text into `DiffHunk` values with per-line numbering and inline
/// highlights. Shared by every producer of a diff — the staging lists and a commit's file diff.
nonisolated enum GitDiffHunkParser {

	private static let hunkHeaderRegex = try? NSRegularExpression(
		pattern: #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
	)

	// MARK: - Parse

	/// Parses `git diff` / `git show` output into hunks. Output that describes no line changes — an
	/// empty file being added or deleted, a mode-only change — carries no `@@` header and yields no
	/// hunks.
	static func parse(_ diffOutput: String) -> [DiffHunk] {
		var hunks: [DiffHunk] = []
		var lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

		// `git diff` terminates its output with a newline, so the final split component is the empty
		// remainder after that newline rather than a line of the diff. Every content line git emits
		// carries a " ", "+" or "-" prefix, so an empty component can only be that terminator —
		// keeping it would append a phantom blank context line to the last hunk (a 119-line added
		// file would parse as 120 lines, contradicting its own "@@ -0,0 +1,119 @@" header).
		if lines.last?.isEmpty == true {
			lines.removeLast()
		}

		var currentHunkLines: [String] = []
		var linesWithoutTrailingNewline: Set<Int> = []
		var currentHunkHeader: String?
		var hunkHeaderParts: (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)?

		func saveCurrentHunk() {
			guard let header = currentHunkHeader, let parts = hunkHeaderParts else {
				return
			}

			let diffLines = numberedDiffLines(
				currentHunkLines,
				hunkHeader: header,
				oldStart: parts.oldStart,
				newStart: parts.newStart,
				linesWithoutTrailingNewline: linesWithoutTrailingNewline
			)
			hunks.append(
				DiffHunk(
					header: header,
					oldStart: parts.oldStart,
					oldCount: parts.oldCount,
					newStart: parts.newStart,
					newCount: parts.newCount,
					lines: InlineDiffHighlighter.apply(to: diffLines)
				)
			)
		}

		for line in lines {
			if line.hasPrefix("@@") {
				saveCurrentHunk()
				currentHunkHeader = line
				hunkHeaderParts = parseHunkHeader(line)
				currentHunkLines = []
				linesWithoutTrailingNewline = []
			}
			else if currentHunkHeader != nil {
				// Content lines are checked first: a line whose own text starts with a backslash
				// still arrives prefixed by "+", "-" or " ", so only a bare backslash is a marker.
				if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
					currentHunkLines.append(line)
				}
				else if line.hasPrefix("\\") {
					// A hunk can carry two markers — one for the old side's last line and one for the
					// new side's — so this records against the preceding line rather than the hunk.
					if let lastIndex = currentHunkLines.indices.last {
						linesWithoutTrailingNewline.insert(lastIndex)
					}
				}
				else if line.isEmpty {
					currentHunkLines.append(" ")
				}
			}
		}

		saveCurrentHunk()
		return hunks
	}

	// MARK: - Line Numbering

	/// Assigns old/new line numbers to a hunk's raw lines, advancing each side only for the lines
	/// that exist on it.
	static func numberedDiffLines(
		_ rawLines: [String],
		hunkHeader: String,
		oldStart: Int,
		newStart: Int,
		linesWithoutTrailingNewline: Set<Int> = []
	) -> [DiffLine] {
		var oldLine = oldStart
		var newLine = newStart
		var result: [DiffLine] = []
		result.reserveCapacity(rawLines.count)

		for (index, rawLine) in rawLines.enumerated() {
			let oldNum: Int?
			let newNum: Int?

			if rawLine.hasPrefix("+") {
				oldNum = nil
				newNum = newLine
				newLine += 1
			}
			else if rawLine.hasPrefix("-") {
				oldNum = oldLine
				newNum = nil
				oldLine += 1
			}
			else {
				oldNum = oldLine
				newNum = newLine
				oldLine += 1
				newLine += 1
			}

			result.append(DiffLine(
				rawLine: rawLine,
				id: "\(hunkHeader):\(index)",
				oldLineNumber: oldNum,
				newLineNumber: newNum,
				hasNoNewlineAtEndOfFile: linesWithoutTrailingNewline.contains(index)
			))
		}

		return result
	}

	// MARK: - Private Helpers

	private static func parseHunkHeader(_ header: String) -> (
		oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
	) {
		guard
			let regex = hunkHeaderRegex,
			let match = regex.firstMatch(
				in: header,
				range: NSRange(header.startIndex..., in: header)
			)
		else {
			return (0, 0, 0, 0)
		}

		let oldStart = extractInt(from: header, match: match, group: 1)
		let oldCount = extractInt(from: header, match: match, group: 2)
		let newStart = extractInt(from: header, match: match, group: 3)
		let newCount = extractInt(from: header, match: match, group: 4)

		return (oldStart, oldCount, newStart, newCount)
	}

	private static func extractInt(from string: String, match: NSTextCheckingResult, group: Int) -> Int {
		guard
			let range = Range(match.range(at: group), in: string),
			!range.isEmpty
		else {
			return 0
		}

		return Int(string[range]) ?? 0
	}
}
