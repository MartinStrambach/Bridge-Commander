import Testing

@testable import TerminalFeature

struct PromptGlyphScannerTests {
	/// The input box Claude draws when it is waiting: carriage return, cursor down, then the glyph.
	private static let promptFrame = Array("\r\u{1B}[1B\u{1B}[39m❯\u{A0}".utf8)

	@Test func findsGlyphInAPromptFrame() {
		var scanner = PromptGlyphScanner()
		let found = scanner.scan(Self.promptFrame)
		#expect(found)
	}

	@Test func ignoresOutputWithoutTheGlyph() {
		var scanner = PromptGlyphScanner()
		let found = scanner.scan(Array("✻ Thinking… (12s · 3.1k tokens)".utf8))
		#expect(!found)
	}

	@Test func findsGlyphSplitAcrossReads() {
		// A read boundary landing inside the glyph's three UTF-8 bytes must not hide it.
		let bytes = Self.promptFrame
		let glyphStart = bytes.count - 5 // the glyph is followed by a two-byte NBSP

		for split in (glyphStart ... glyphStart + 2) {
			var scanner = PromptGlyphScanner()
			let head = scanner.scan(bytes[..<split])
			let tail = scanner.scan(bytes[split...])
			#expect(head || tail, "glyph lost when split at byte \(split)")
		}
	}

	@Test func reportsOnlyTheSliceThatCompletesTheGlyph() {
		var scanner = PromptGlyphScanner()
		let lead = scanner.scan([0xE2, 0x9D])
		#expect(!lead)

		let completion = scanner.scan([0xAF])
		#expect(completion)

		// The window must not keep matching once the glyph has been consumed.
		let afterwards = scanner.scan([0xAF])
		#expect(!afterwards)
	}

	@Test func doesNotMatchOtherMultiByteCharacters() {
		var scanner = PromptGlyphScanner()
		// ❮ (U+276E) and ⏺ (U+23FA) share a lead byte or a continuation byte with ❯.
		let found = scanner.scan(Array("❮ ⏺ ─ │ ╭".utf8))
		#expect(!found)
	}
}
