/// Finds Claude's prompt glyph (`❯`, U+276F — `E2 9D AF` in UTF-8) in a stream of terminal output.
///
/// The grid is the better place to look for the prompt, since it says where the glyph sits and what
/// is still on screen. This exists for the case where the grid can't answer: while the user is
/// scrolled back through history, the visible rows are no longer the live screen.
///
/// A rolling window carries the trailing bytes of each slice into the next call, so a glyph whose
/// encoding straddles two reads is still found.
struct PromptGlyphScanner {
	private var previousBytes: (UInt8, UInt8) = (0, 0)

	/// Whether `bytes` completed an occurrence of the glyph, counting one that began in earlier calls.
	mutating func scan(_ bytes: some Sequence<UInt8>) -> Bool {
		var (first, second) = previousBytes
		var found = false
		for byte in bytes {
			if first == 0xE2, second == 0x9D, byte == 0xAF {
				found = true
			}
			first = second
			second = byte
		}
		previousBytes = (first, second)
		return found
	}
}
