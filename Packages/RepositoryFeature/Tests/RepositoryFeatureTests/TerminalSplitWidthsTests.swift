import Testing
@testable import RepositoryFeature

@Suite("Terminal split widths")
struct TerminalSplitWidthsTests {
	@Test("two panes get halves and three get thirds, in whole points that fill the width")
	func equalShares() {
		#expect(TerminalSplitWidths(count: 1).widths(total: 901) == [901])
		#expect(TerminalSplitWidths(count: 2).widths(total: 905) == [450, 450])
		#expect(TerminalSplitWidths(count: 3).widths(total: 1010) == [333, 333, 334])
		#expect(TerminalSplitWidths(count: 3).widths(total: 1010.5).reduce(0, +) == 1000.5)
	}

	@Test("a dragged divider moves width between its two neighbours only")
	func dragMovesWidthBetweenNeighbours() {
		let dragged = TerminalSplitWidths(count: 3).draggingDivider(after: 0, by: 100, total: 1010)

		#expect(dragged.widths(total: 1010) == [433, 233, 334])
	}

	@Test("a drag stops at the narrowest a pane may be")
	func dragStopsAtMinimum() {
		let shares = TerminalSplitWidths(count: 2)

		#expect(shares.draggingDivider(after: 0, by: 5000, total: 1005).widths(total: 1005) == [840, 160])
		#expect(shares.draggingDivider(after: 0, by: -5000, total: 1005).widths(total: 1005) == [160, 840])
		// With no room for two panes of that width, the drag has nowhere to go.
		#expect(shares.draggingDivider(after: 0, by: 50, total: 205) == shares)
	}

	@Test("a drag on a divider that is not there changes nothing")
	func dragOutOfRange() {
		let shares = TerminalSplitWidths(count: 2)

		#expect(shares.draggingDivider(after: 1, by: 40, total: 1005) == shares)
	}
}
