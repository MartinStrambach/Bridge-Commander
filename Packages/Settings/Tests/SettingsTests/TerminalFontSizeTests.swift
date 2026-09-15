import Testing
@testable import Settings

@Suite("TerminalFontSize")
struct TerminalFontSizeTests {

	@Test("a value inside the range is left alone")
	func clampedKeepsSupportedSizes() {
		#expect(TerminalFontSize.clamped(13) == 13)
		#expect(TerminalFontSize.clamped(TerminalFontSize.minimum) == TerminalFontSize.minimum)
		#expect(TerminalFontSize.clamped(TerminalFontSize.maximum) == TerminalFontSize.maximum)
	}

	@Test("a value outside the range is pulled to the nearest bound")
	func clampedPinsOutOfRangeSizes() {
		#expect(TerminalFontSize.clamped(2) == TerminalFontSize.minimum)
		#expect(TerminalFontSize.clamped(400) == TerminalFontSize.maximum)
		// Defends the cell-size division in SwiftTerm's resetFont, which anything writing to
		// user defaults could otherwise reach.
		#expect(TerminalFontSize.clamped(0) == TerminalFontSize.minimum)
		#expect(TerminalFontSize.clamped(-10) == TerminalFontSize.minimum)
	}

	@Test("zooming steps by one point and stops at the bounds")
	func zoomingStepsAndStops() {
		#expect(TerminalFontSize.zoomedIn(from: 13) == 14)
		#expect(TerminalFontSize.zoomedOut(from: 13) == 12)
		#expect(TerminalFontSize.zoomedIn(from: TerminalFontSize.maximum) == TerminalFontSize.maximum)
		#expect(TerminalFontSize.zoomedOut(from: TerminalFontSize.minimum) == TerminalFontSize.minimum)
	}

	@Test("the default is the size SwiftTerm rendered at before the setting existed")
	func defaultMatchesSwiftTermDefault() {
		// NSFont.systemFontSize, which is what SwiftTerm's FontSet.defaultFont asks for.
		#expect(TerminalFontSize.default == 13)
	}
}
