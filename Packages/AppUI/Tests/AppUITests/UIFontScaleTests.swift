import SwiftUI
import Testing
@testable import AppUI

@Suite("UIFontScale")
struct UIFontScaleTests {

	@Test("scale 1 keeps the text style itself, so an untouched install renders as before")
	func unscaledIsTheTextStyle() {
		#expect(UIFontScale.font(.caption, scale: 1) == .system(.caption))
		#expect(
			UIFontScale.font(.body, design: .monospaced, weight: .semibold, scale: 1)
				== .system(.body, design: .monospaced, weight: .semibold)
		)
	}

	@Test("other scales multiply the style's macOS point size")
	func scaledIsAPointSize() {
		#expect(UIFontScale.font(.caption, scale: 1.5) == .system(size: 15))
		#expect(UIFontScale.font(.body, design: .monospaced, scale: 2) == .system(size: 26, design: .monospaced))
	}

	@Test("a scaled headline stays bold, as the text style is on macOS")
	func scaledHeadlineIsBold() {
		#expect(UIFontScale.font(.headline, scale: 2) == .system(size: 26, weight: .bold))
		#expect(UIFontScale.font(.headline, weight: .medium, scale: 2) == .system(size: 26, weight: .medium))
	}

	@Test("scaled buttons start from the title size AppKit uses for their control size")
	func controlPointSizes() {
		#expect(UIFontScale.controlPointSize(for: .small) == 11)
		#expect(UIFontScale.controlPointSize(for: .regular) == 13)
		#expect(UIFontScale.controlPointSize(for: .mini) < UIFontScale.controlPointSize(for: .small))
	}
}
