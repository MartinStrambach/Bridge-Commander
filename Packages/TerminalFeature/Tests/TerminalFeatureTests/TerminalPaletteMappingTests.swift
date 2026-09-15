import AppKit
import Foundation
import SwiftTerm
import Testing

@testable import TerminalFeature

@Suite("TerminalPaletteMapping")
struct TerminalPaletteMappingTests {
	private static func palette(count: Int) -> [NSColor] {
		(0 ..< count).map { index in
			NSColor(srgbRed: Double(index) / 16, green: 0.5, blue: 0.25, alpha: 1)
		}
	}

	@Test("a full palette of sixteen converts")
	func convertsFullPalette() throws {
		let converted = try #require(TerminalPaletteMapping.swiftTermColors(from: Self.palette(count: 16)))

		#expect(converted.count == 16)
	}

	@Test("a palette that is not exactly sixteen colors is rejected")
	func rejectsWrongLength() {
		// SwiftTerm's installColors silently no-ops on any other length, so catching it here is
		// the difference between a reported problem and a theme that quietly does nothing.
		for count in [0, 1, 8, 15, 17] {
			#expect(
				TerminalPaletteMapping.swiftTermColors(from: Self.palette(count: count)) == nil,
				"expected \(count) colors to be rejected"
			)
		}
	}

	@Test("8-bit components survive the conversion")
	func preservesComponents() throws {
		let color = try #require(
			TerminalPaletteMapping.swiftTermColor(from: NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1))
		)

		// SwiftTerm stores 16 bits per channel, scaling each 8-bit value by 257.
		#expect(color.red == 255 * 257)
		#expect(color.green == 0)
		#expect(color.blue == 128 * 257)
	}

	@Test("a grayscale color converts instead of raising on a missing RGB component")
	func convertsGrayscale() throws {
		// Terminal.app stores some profile colors in Generic Gray.
		let color = try #require(TerminalPaletteMapping.swiftTermColor(from: NSColor(white: 1, alpha: 1)))

		#expect(color.red == 255 * 257)
		#expect(color.green == 255 * 257)
		#expect(color.blue == 255 * 257)
	}

	@Test("alpha is ignored, because SwiftTerm's color type has no alpha channel")
	func ignoresAlpha() throws {
		let opaque = try #require(
			TerminalPaletteMapping.swiftTermColor(from: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
		)
		let translucent = try #require(
			TerminalPaletteMapping.swiftTermColor(from: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
		)

		#expect(opaque == translucent)
	}
}
