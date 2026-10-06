import Foundation
import Testing
@testable import Settings

@Suite("UIFontSize")
struct UIFontSizeTests {

	@Test("the default is macOS's body size, which is scale 1")
	func defaultIsUnscaled() {
		#expect(UIFontSize.default == 13)
		#expect(UIFontSize.scale(for: UIFontSize.default) == 1)
	}

	@Test("values outside the range are clamped, including ones read back from user defaults")
	func clamps() {
		#expect(UIFontSize.clamped(15) == 15)
		#expect(UIFontSize.clamped(0) == UIFontSize.minimum)
		#expect(UIFontSize.clamped(-4) == UIFontSize.minimum)
		#expect(UIFontSize.clamped(400) == UIFontSize.maximum)
	}

	@Test("the scale is the ratio to the default size, taken after clamping")
	func scale() {
		#expect(UIFontSize.scale(for: 26) == CGFloat(UIFontSize.maximum / UIFontSize.default))
		#expect(abs(UIFontSize.scale(for: 16) - 16.0 / 13.0) < 0.0001)
	}
}
