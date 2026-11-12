import Testing

@testable import TerminalFeature

@Suite("ClaudeQuoteGutter")
struct ClaudeQuoteGutterTests {

	@Test("a quote selected across rows loses the bar on its continuation rows")
	func stripsContinuationRows() {
		let copied = "list CountryRankingWidgetViewTests in\n  ▎ decision.json's iOS snapshots"

		#expect(
			ClaudeQuoteGutter.strip(copied)
				== "list CountryRankingWidgetViewTests in\ndecision.json's iOS snapshots"
		)
	}

	@Test("a selection starting at the bar loses it on the first row too")
	func stripsTheFirstRow() {
		#expect(ClaudeQuoteGutter.strip("  ▎ review MOB-4330\n  ▎ Change no code") == "review MOB-4330\nChange no code")
	}

	@Test("a nested quote loses every bar")
	func stripsNestedBars() {
		#expect(ClaudeQuoteGutter.strip("  ▎ ▎ inner") == "inner")
	}

	@Test("the padding after quoted text goes with the bar")
	func trimsPaddingOfQuotedLines() {
		#expect(ClaudeQuoteGutter.strip("  ▎ short   \nplain   ") == "short\nplain   ")
	}

	@Test("a bar inside a line is text, not a gutter")
	func keepsABarMidLine() {
		#expect(ClaudeQuoteGutter.strip("progress ▎▎▎ 30%") == "progress ▎▎▎ 30%")
	}

	@Test("text without a bar is untouched")
	func leavesPlainTextAlone() {
		#expect(ClaudeQuoteGutter.strip("  indented\n\nnext") == "  indented\n\nnext")
	}
}
