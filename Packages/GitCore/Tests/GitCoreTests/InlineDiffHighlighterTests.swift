import Foundation
import Testing
@testable import GitCore

@Suite("InlineDiffHighlighter")
struct InlineDiffHighlighterTests {

	// MARK: - Helpers

	/// Builds the numbered lines the parser would hand to the highlighter.
	private func lines(_ rawLines: [String]) -> [DiffLine] {
		rawLines.enumerated().map { index, raw in
			DiffLine(rawLine: raw, id: "h:\(index)", oldLineNumber: nil, newLineNumber: nil)
		}
	}

	/// The substrings a line would render with a highlight background.
	/// Asserting on text rather than `String.Index` ranges keeps the tests about behavior.
	private func highlights(_ line: DiffLine) -> [String] {
		line.inlineChanges.map { String(line.content[$0]) }
	}

	// MARK: - Basic pairing

	@Test("a single deletion/addition pair highlights only the changed token")
	func singlePairHighlightsChangedToken() {
		let result = InlineDiffHighlighter.apply(to: lines([
			"-let value = oldFunction()",
			"+let value = newFunction()",
		]))

		#expect(highlights(result[0]) == ["oldFunction"])
		#expect(highlights(result[1]) == ["newFunction"])
	}

	@Test("lines below the similarity threshold are not highlighted")
	func dissimilarLinesAreNotHighlighted() {
		let result = InlineDiffHighlighter.apply(to: lines([
			"-completely unrelated content here",
			"+xyz",
		]))

		#expect(highlights(result[0]).isEmpty)
		#expect(highlights(result[1]).isEmpty)
	}

	@Test("context lines are never highlighted")
	func contextLinesAreNeverHighlighted() {
		let result = InlineDiffHighlighter.apply(to: lines([
			" let untouched = value",
			" let alsoUntouched = other",
		]))

		#expect(result.allSatisfy { $0.inlineChanges.isEmpty })
	}

	@Test("a block with deletions but no additions is not highlighted")
	func deletionOnlyBlockIsNotHighlighted() {
		let result = InlineDiffHighlighter.apply(to: lines([
			"-let removed = one",
			"-let alsoRemoved = two",
		]))

		#expect(result.allSatisfy { $0.inlineChanges.isEmpty })
	}

	@Test("blocks separated by context are highlighted independently")
	func blocksSeparatedByContextAreIndependent() {
		let result = InlineDiffHighlighter.apply(to: lines([
			"-let first = oldOne()",
			"+let first = newOne()",
			" let context = untouched",
			"-let second = oldTwo()",
			"+let second = newTwo()",
		]))

		#expect(highlights(result[0]) == ["oldOne"])
		#expect(highlights(result[1]) == ["newOne"])
		#expect(highlights(result[2]).isEmpty)
		#expect(highlights(result[3]) == ["oldTwo"])
		#expect(highlights(result[4]) == ["newTwo"])
	}

	// MARK: - Range post-processing

	@Test("changed ranges separated by a tiny gap are merged into one highlight")
	func tinyGapsBetweenRangesAreMerged() {
		// `foo` and `bar` both change, separated only by `.` — one highlight, not two.
		let result = InlineDiffHighlighter.apply(to: lines([
			"-value = foo.bar",
			"+value = baz.qux",
		]))

		#expect(highlights(result[0]) == ["foo.bar"])
		#expect(highlights(result[1]) == ["baz.qux"])
	}

	@Test("highlight boundaries are trimmed of surrounding whitespace")
	func highlightBoundariesAreTrimmed() {
		// The inserted run starts and ends on a space token; the highlight must not include them.
		let result = InlineDiffHighlighter.apply(to: lines([
			"-if (a) {",
			"+if (a && b) {",
		]))

		#expect(highlights(result[0]).isEmpty)
		#expect(highlights(result[1]) == ["&& b"])
	}

	// MARK: - Pairing strategy

	@Test("the most similar candidate wins, not the positional one")
	func mostSimilarCandidateWins() {
		// del[0] is a near-perfect match for add[1]; positional pairing would pick add[0].
		let result = InlineDiffHighlighter.apply(to: lines([
			"-let alpha = compute(alpha: value)",
			"+let beta = compute(beta: value)",
			"+let alpha = compute(alpha: other)",
		]))

		#expect(highlights(result[0]) == ["value"])
		#expect(highlights(result[2]) == ["other"])
		#expect(highlights(result[1]).isEmpty, "the unmatched addition stays unhighlighted")
	}

	// MARK: - Work bounds

	@Test("blocks exceeding the pair-work budget fall back to positional pairing")
	func oversizedBlocksFallBackToPositionalPairing() {
		let input = lines([
			"-let alpha = compute(alpha: value)",
			"+let beta = compute(beta: value)",
			"+let alpha = compute(alpha: other)",
		])

		let result = InlineDiffHighlighter.apply(to: input, maxPairWork: 1)

		// Paired by position: del[0] <-> add[0], so both `alpha` tokens are highlighted...
		#expect(highlights(result[0]) == ["alpha", "alpha"])
		#expect(highlights(result[1]) == ["beta", "beta"])
		// ...and the second addition is left out entirely.
		#expect(highlights(result[2]).isEmpty)
	}

	@Test("lines longer than the length budget are left unhighlighted")
	func overlongLinesAreSkipped() {
		let long = String(repeating: "abc ", count: 50)
		let result = InlineDiffHighlighter.apply(
			to: lines(["-\(long)old", "+\(long)new"]),
			maxLineLength: 10
		)

		#expect(result.allSatisfy { $0.inlineChanges.isEmpty })
	}

	@Test("a large contiguous change block completes quickly", .timeLimit(.minutes(1)))
	func largeBlockCompletesQuickly() {
		// A reformat-style block: 400 deletions followed by 400 additions. The all-pairs
		// similarity matrix makes this quadratic, which is what the work budget bounds.
		var raw: [String] = []
		for index in 0 ..< 400 {
			raw.append("-    let someValueName\(index) = computeSomething(with: first, and: second) // \(index)")
		}
		for index in 0 ..< 400 {
			raw.append("+    let someValueName\(index) = computeSomethingElse(with: first, and: third) // \(index)")
		}
		let input = lines(raw)

		let started = ContinuousClock.now
		let result = InlineDiffHighlighter.apply(to: input)
		let elapsed = ContinuousClock.now - started

		#expect(elapsed < .seconds(1.5), "took \(elapsed) — inline highlighting is quadratic again")
		#expect(result.count == input.count)
		// The fallback still produces useful highlights rather than giving up.
		#expect(!result[0].inlineChanges.isEmpty)
	}

	// MARK: - Invariants

	@Test("line identity, order, and content are preserved")
	func linePropertiesArePreserved() {
		let input = lines([
			"-let value = oldFunction()",
			"+let value = newFunction()",
			" let context = untouched",
		])

		let result = InlineDiffHighlighter.apply(to: input)

		#expect(result.count == input.count)
		#expect(result.map(\.id) == input.map(\.id))
		#expect(result.map(\.rawLine) == input.map(\.rawLine))
		#expect(result.map(\.content) == input.map(\.content))
		#expect(result.map(\.type) == input.map(\.type))
	}
}
