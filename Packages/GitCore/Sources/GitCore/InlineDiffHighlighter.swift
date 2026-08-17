import Foundation

/// Computes the intra-line (word-level) highlight ranges shown inside a diff hunk.
///
/// Within a run of deletions immediately followed by additions, every deletion is a candidate
/// partner for every addition, so the search is inherently O(deletions x additions). Each
/// comparison is itself a token LCS, which makes the naive form quadratic-on-quadratic and turns
/// a large reformat-style block (a regenerated file, a re-indent, a moved code block) into a
/// multi-second stall. Three things keep it bounded:
///
/// 1. Each line is tokenized once and its tokens interned to `Int`, so the LCS inner loop compares
///    integers instead of doing grapheme-aware `Substring` comparison.
/// 2. A cheap O(m+n) token-multiset score prunes candidate pairs before any LCS runs. Multiset
///    intersection is an upper bound on token LCS, so pruning on it can never discard a pair the
///    exact measure would have accepted.
/// 3. Blocks whose candidate count exceeds `maxPairWork` skip the search entirely and pair by
///    position, which is the sensible reading of a wholesale rewrite anyway.
nonisolated enum InlineDiffHighlighter {

	/// Fraction of shared tokens a pair needs before it is considered the "same" line, edited.
	private static let similarityThreshold = 0.40

	/// Candidate-pair budget per block (deletions x additions) before falling back to positional
	/// pairing. 4,000 keeps the exhaustive search on blocks up to roughly 60x60 lines.
	static let defaultMaxPairWork = 4_000

	/// Lines longer than this (in UTF-8 bytes) are never highlighted. A single pair of minified or
	/// generated lines can otherwise dominate the whole diff.
	static let defaultMaxLineLength = 2_000

	// MARK: - Entry Point

	/// Returns `lines` with inline highlight ranges filled in on changed lines.
	///
	/// Line count, order, ids and content are preserved; only `inlineChanges` is populated.
	static func apply(
		to lines: [DiffLine],
		maxPairWork: Int = defaultMaxPairWork,
		maxLineLength: Int = defaultMaxLineLength
	) -> [DiffLine] {
		var result = lines
		var index = 0

		while index < lines.count {
			let deletionStart = index
			while index < lines.count, lines[index].type == .deletion { index += 1 }
			let deletionEnd = index

			let additionStart = index
			while index < lines.count, lines[index].type == .addition { index += 1 }
			let additionEnd = index

			if deletionEnd > deletionStart, additionEnd > additionStart {
				highlightBlock(
					lines: lines,
					deletions: deletionStart ..< deletionEnd,
					additions: additionStart ..< additionEnd,
					maxPairWork: maxPairWork,
					maxLineLength: maxLineLength,
					into: &result
				)
			}

			if index == deletionStart { index += 1 }
		}

		return result
	}

	// MARK: - Block Matching

	private static func highlightBlock(
		lines: [DiffLine],
		deletions: Range<Int>,
		additions: Range<Int>,
		maxPairWork: Int,
		maxLineLength: Int,
		into result: inout [DiffLine]
	) {
		// Interning is shared across the block so ids are comparable between any two lines in it.
		var interner = TokenInterner()
		let deleted = deletions.map { TokenizedLine(lines[$0].content, interner: &interner) }
		let added = additions.map { TokenizedLine(lines[$0].content, interner: &interner) }

		func isEligible(_ line: TokenizedLine) -> Bool {
			line.content.utf8.count <= maxLineLength
		}

		var pairs: [(similarity: Double, deletion: Int, addition: Int)] = []
		var lcsBuffer: [Int] = []

		if deleted.count * added.count > maxPairWork {
			// Bounded fallback: pair by position.
			for offset in 0 ..< min(deleted.count, added.count) {
				let old = deleted[offset], new = added[offset]
				guard isEligible(old), isEligible(new) else { continue }
				let score = similarity(old, new, buffer: &lcsBuffer)
				if score >= similarityThreshold {
					pairs.append((score, offset, offset))
				}
			}
		}
		else {
			for (deletionOffset, old) in deleted.enumerated() where isEligible(old) {
				for (additionOffset, new) in added.enumerated() where isEligible(new) {
					// Upper bound first — it rejects most pairs without touching the LCS.
					guard multisetSimilarityBound(old, new) >= similarityThreshold else { continue }
					let score = similarity(old, new, buffer: &lcsBuffer)
					if score >= similarityThreshold {
						pairs.append((score, deletionOffset, additionOffset))
					}
				}
			}
		}

		// Greedy match: strongest pair first, each line used at most once.
		pairs.sort { $0.similarity > $1.similarity }
		var usedDeletions = Set<Int>()
		var usedAdditions = Set<Int>()

		for pair in pairs {
			guard !usedDeletions.contains(pair.deletion), !usedAdditions.contains(pair.addition) else {
				continue
			}

			usedDeletions.insert(pair.deletion)
			usedAdditions.insert(pair.addition)

			let old = deleted[pair.deletion]
			let new = added[pair.addition]
			let (oldRanges, newRanges) = changedRanges(old, new)
			guard !oldRanges.isEmpty || !newRanges.isEmpty else { continue }

			let deletionIndex = deletions.lowerBound + pair.deletion
			let additionIndex = additions.lowerBound + pair.addition
			result[deletionIndex] = lines[deletionIndex].withInlineChanges(oldRanges)
			result[additionIndex] = lines[additionIndex].withInlineChanges(newRanges)
		}
	}

	// MARK: - Similarity

	/// Token-multiset overlap. Because a token LCS can never match more occurrences of a token than
	/// both sides contain, this is an upper bound on `similarity` and safe to prune with.
	private static func multisetSimilarityBound(_ old: TokenizedLine, _ new: TokenizedLine) -> Double {
		guard !old.tokenIds.isEmpty, !new.tokenIds.isEmpty else {
			return 0
		}

		let (smaller, larger) = old.tokenCounts.count <= new.tokenCounts.count
			? (old.tokenCounts, new.tokenCounts)
			: (new.tokenCounts, old.tokenCounts)

		var shared = 0
		for (token, count) in smaller {
			if let otherCount = larger[token] {
				shared += min(count, otherCount)
			}
		}

		return 2.0 * Double(shared) / Double(old.tokenIds.count + new.tokenIds.count)
	}

	/// Exact token-LCS similarity, using two rolling rows out of a caller-owned buffer.
	private static func similarity(
		_ old: TokenizedLine,
		_ new: TokenizedLine,
		buffer: inout [Int]
	) -> Double {
		let oldCount = old.tokenIds.count
		let newCount = new.tokenIds.count
		guard oldCount > 0, newCount > 0 else {
			return 0
		}

		let rowWidth = newCount + 1
		if buffer.count < 2 * rowWidth {
			buffer = [Int](repeating: 0, count: 2 * rowWidth)
		}
		for slot in 0 ..< (2 * rowWidth) { buffer[slot] = 0 }

		var previousRow = 0
		var currentRow = rowWidth

		old.tokenIds.withUnsafeBufferPointer { oldTokens in
			new.tokenIds.withUnsafeBufferPointer { newTokens in
				buffer.withUnsafeMutableBufferPointer { table in
					for oldIndex in 1 ... oldCount {
						table[currentRow] = 0
						let oldToken = oldTokens[oldIndex - 1]
						for newIndex in 1 ... newCount {
							table[currentRow + newIndex] = oldToken == newTokens[newIndex - 1]
								? table[previousRow + newIndex - 1] + 1
								: max(table[previousRow + newIndex], table[currentRow + newIndex - 1])
						}
						swap(&previousRow, &currentRow)
					}
				}
			}
		}

		return 2.0 * Double(buffer[previousRow + newCount]) / Double(oldCount + newCount)
	}

	// MARK: - Changed Ranges

	private static func changedRanges(
		_ old: TokenizedLine,
		_ new: TokenizedLine
	) -> (old: [Range<String.Index>], new: [Range<String.Index>]) {
		let oldCount = old.tokenIds.count
		let newCount = new.tokenIds.count
		guard oldCount > 0, newCount > 0 else {
			return ([], [])
		}

		// Full Wagner-Fischer table, flat rather than nested so it is a single allocation.
		let rowWidth = newCount + 1
		var table = [Int](repeating: 0, count: (oldCount + 1) * rowWidth)
		old.tokenIds.withUnsafeBufferPointer { oldTokens in
			new.tokenIds.withUnsafeBufferPointer { newTokens in
				table.withUnsafeMutableBufferPointer { dp in
					for oldIndex in 1 ... oldCount {
						let row = oldIndex * rowWidth
						let previousRow = (oldIndex - 1) * rowWidth
						let oldToken = oldTokens[oldIndex - 1]
						for newIndex in 1 ... newCount {
							dp[row + newIndex] = oldToken == newTokens[newIndex - 1]
								? dp[previousRow + newIndex - 1] + 1
								: max(dp[previousRow + newIndex], dp[row + newIndex - 1])
						}
					}
				}
			}
		}

		// Backtrack to mark the tokens that survived.
		var oldMatched = [Bool](repeating: false, count: oldCount)
		var newMatched = [Bool](repeating: false, count: newCount)
		var oldIndex = oldCount
		var newIndex = newCount
		while oldIndex > 0, newIndex > 0 {
			if old.tokenIds[oldIndex - 1] == new.tokenIds[newIndex - 1] {
				oldMatched[oldIndex - 1] = true
				newMatched[newIndex - 1] = true
				oldIndex -= 1
				newIndex -= 1
			}
			else if table[(oldIndex - 1) * rowWidth + newIndex] >= table[oldIndex * rowWidth + newIndex - 1] {
				oldIndex -= 1
			}
			else {
				newIndex -= 1
			}
		}

		return (
			postProcess(unmatchedRanges(old, matched: oldMatched), of: old),
			postProcess(unmatchedRanges(new, matched: newMatched), of: new)
		)
	}

	private static func postProcess(
		_ ranges: [Range<String.Index>],
		of line: TokenizedLine
	) -> [Range<String.Index>] {
		trimWhitespaceBoundaries(mergeSmallGaps(ranges, of: line), in: line.content)
	}

	private static func unmatchedRanges(
		_ line: TokenizedLine,
		matched: [Bool]
	) -> [Range<String.Index>] {
		var ranges: [Range<String.Index>] = []
		for (range, isMatched) in zip(line.tokenRanges, matched) {
			guard !isMatched else { continue }
			if let last = ranges.last, last.upperBound == range.lowerBound {
				ranges[ranges.count - 1] = last.lowerBound ..< range.upperBound
			}
			else {
				ranges.append(range)
			}
		}
		return ranges
	}

	/// Merges highlights that are only separated by a couple of characters, or by a single
	/// punctuation token, so `foo.bar` -> `baz.qux` reads as one change rather than two.
	private static func mergeSmallGaps(
		_ ranges: [Range<String.Index>],
		of line: TokenizedLine
	) -> [Range<String.Index>] {
		guard ranges.count >= 2 else {
			return ranges
		}

		let content = line.content
		let tokenRanges = line.tokenRanges
		var result = [ranges[0]]
		// Token ranges and highlight ranges both increase, so one forward cursor covers all gaps.
		var cursor = 0

		for current in ranges.dropFirst() {
			let previous = result[result.count - 1]

			while cursor < tokenRanges.count, tokenRanges[cursor].lowerBound < previous.upperBound {
				cursor += 1
			}

			var gapTokenCount = 0
			var firstGapToken: Range<String.Index>?
			var scan = cursor
			while scan < tokenRanges.count, tokenRanges[scan].upperBound <= current.lowerBound {
				gapTokenCount += 1
				if firstGapToken == nil { firstGapToken = tokenRanges[scan] }
				scan += 1
			}

			let gapLength = content.distance(from: previous.upperBound, to: current.lowerBound)
			let isSinglePunctuation = gapTokenCount == 1 && firstGapToken.map {
				content[$0].allSatisfy { !$0.isLetter && !$0.isNumber && $0 != "_" }
			} == true

			if gapLength <= 2 || isSinglePunctuation {
				result[result.count - 1] = previous.lowerBound ..< current.upperBound
			}
			else {
				result.append(current)
			}
		}

		return result
	}

	private static func trimWhitespaceBoundaries(
		_ ranges: [Range<String.Index>],
		in content: String
	) -> [Range<String.Index>] {
		var result: [Range<String.Index>] = []
		for range in ranges {
			var lower = range.lowerBound
			var upper = range.upperBound
			while lower < upper, content[lower].isWhitespace { lower = content.index(after: lower) }
			while upper > lower, content[content.index(before: upper)].isWhitespace {
				upper = content.index(before: upper)
			}
			if lower < upper { result.append(lower ..< upper) }
		}
		return result
	}

	// MARK: - Tokenization

	/// Maps equal token texts to a shared `Int` id so comparisons are integer equality.
	private struct TokenInterner {
		private var ids: [Substring: Int] = [:]

		mutating func id(for token: Substring) -> Int {
			if let existing = ids[token] {
				return existing
			}

			let next = ids.count
			ids[token] = next
			return next
		}
	}

	/// A line's tokens, tokenized exactly once per block.
	private struct TokenizedLine {
		let content: String
		let tokenRanges: [Range<String.Index>]
		let tokenIds: [Int]
		let tokenCounts: [Int: Int]

		init(_ content: String, interner: inout TokenInterner) {
			self.content = content

			var ranges: [Range<String.Index>] = []
			var ids: [Int] = []
			var counts: [Int: Int] = [:]

			var index = content.startIndex
			while index < content.endIndex {
				let character = content[index]
				var end = content.index(after: index)

				if character.isLetter || character.isNumber || character == "_" {
					while end < content.endIndex,
					      content[end].isLetter || content[end].isNumber || content[end] == "_" {
						content.formIndex(after: &end)
					}
				}
				else if character.isWhitespace {
					while end < content.endIndex, content[end].isWhitespace {
						content.formIndex(after: &end)
					}
				}

				let range = index ..< end
				let id = interner.id(for: content[range])
				ranges.append(range)
				ids.append(id)
				counts[id, default: 0] += 1
				index = end
			}

			self.tokenRanges = ranges
			self.tokenIds = ids
			self.tokenCounts = counts
		}
	}
}
