import Foundation

/// Turns raw unified-diff text into `DiffHunk` values with per-line numbering and inline
/// highlights. Shared by every producer of a diff — the staging lists and a commit's file diff.
nonisolated enum GitDiffHunkParser {

	private static let hunkHeaderRegex = try? NSRegularExpression(
		pattern: #"@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@"#
	)

	// MARK: - Parse

	/// Parses `git diff` / `git show` output into hunks.
	///
	/// `fileStatus` only matters for the diff of a whole added or deleted file that git printed
	/// without `@@` headers; every other input is parsed from its headers alone.
	static func parse(_ diffOutput: String, fileStatus: FileChangeStatus) -> [DiffHunk] {
		var hunks: [DiffHunk] = []
		let lines = diffOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

		// For new/deleted files, git doesn't use @@ headers
		// Check if this is a file without traditional hunks
		let hasHunkHeaders = lines.contains { $0.hasPrefix("@@") }

		if !hasHunkHeaders, fileStatus == .added || fileStatus == .deleted {
			return [wholeFileHunk(lines: lines, isAdded: fileStatus == .added)].compactMap { $0 }
		}

		// Standard hunk parsing for modified files
		var currentHunkLines: [String] = []
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
				newStart: parts.newStart
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
			}
			else if currentHunkHeader != nil {
				if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
					currentHunkLines.append(line)
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
		newStart: Int
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
				newLineNumber: newNum
			))
		}

		return result
	}

	// MARK: - Private Helpers

	/// A single hunk covering an added or deleted file that git printed without `@@` headers.
	private static func wholeFileHunk(lines: [String], isAdded: Bool) -> DiffHunk? {
		let diffLines = lines.compactMap { line -> String? in
			if line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") {
				return line
			}
			else if line.isEmpty {
				return " "
			}
			return nil
		}

		guard !diffLines.isEmpty else {
			return nil
		}

		let lineCount = diffLines.count
		let hunkHeader = isAdded ? "@@ -0,0 +1,\(lineCount) @@" : "@@ -1,\(lineCount) +0,0 @@"
		let oldStart = isAdded ? 0 : 1
		let newStart = isAdded ? 1 : 0

		return DiffHunk(
			header: hunkHeader,
			oldStart: oldStart,
			oldCount: isAdded ? 0 : lineCount,
			newStart: newStart,
			newCount: isAdded ? lineCount : 0,
			lines: InlineDiffHighlighter.apply(
				to: numberedDiffLines(diffLines, hunkHeader: hunkHeader, oldStart: oldStart, newStart: newStart)
			)
		)
	}

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
