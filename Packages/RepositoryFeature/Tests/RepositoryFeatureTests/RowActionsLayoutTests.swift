import CoreGraphics
@testable import RepositoryFeature
import Testing

struct RowActionsLayoutTests {
	// Git Actions, Tuist, YouTrack, then five icon buttons: 85+50+70+5×25 + 7×8 = 386.
	private let widths: [CGFloat] = [85, 50, 70, 25, 25, 25, 25, 25]

	@Test
	func oneLineWhenWidthIsUnspecified() {
		#expect(RowActionsLayout.lines(widths: widths, spacing: 8, available: nil) == [0 ..< 8])
	}

	@Test
	func oneLineWhenEverythingFits() {
		#expect(RowActionsLayout.lines(widths: widths, spacing: 8, available: 386) == [0 ..< 8])
	}

	@Test
	func twoBalancedLinesWhenNarrower() {
		// Menus alone are 221 wide, the icons 165; splitting before the third menu would leave
		// 143 vs 235, which is wider.
		#expect(RowActionsLayout.lines(widths: widths, spacing: 8, available: 385) == [0 ..< 3, 3 ..< 8])
	}

	@Test
	func twoLinesEvenWhenNothingFits() {
		#expect(RowActionsLayout.lines(widths: widths, spacing: 8, available: 0).count == 2)
	}

	@Test
	func singleItemStaysOnOneLine() {
		#expect(RowActionsLayout.lines(widths: [40], spacing: 8, available: 10) == [0 ..< 1])
	}
}
