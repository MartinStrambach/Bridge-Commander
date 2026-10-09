import SwiftTerm

/// Reads the pane's live screen on the detector's behalf. Everything specific to the terminal
/// emulator sits here, so the heuristic itself has no opinion about how a row is stored.
///
/// SwiftTerm does not hand out its `Terminal` (since 1.99), so every read is a copy taken under
/// the terminal's lock: the row's text, the grid size, the cursor. Output is parsed on SwiftTerm's
/// IO thread, so two reads in one idle check can see different frames — no worse than a check
/// that lands mid-repaint, which the detector already tolerates.
extension ClaudeAwareTerminalView: PromptScreen {
	var rowCount: Int {
		terminalDimensions.rows
	}

	/// Read from the full state snapshot, the only public read that carries the cursor. It copies
	/// the visible rows too, so it is read once or twice per check, never per row.
	var cursorRow: Int {
		terminalStateSnapshot().cursor.row
	}

	/// Whether the viewport is showing the bottom of the buffer, where the live screen sits.
	/// `canScroll` is false while there is no scrollback to move through, and for the alternate
	/// buffer, both of which only ever display the live screen.
	var isShowingLiveScreen: Bool {
		!canScroll || scrollPosition >= 1
	}

	var isClaudeInForeground: Bool? {
		PtyForegroundProcess.isClaude(ptyDescriptor: process?.childfd ?? -1)
	}

	/// Characters are compared by their first Unicode scalar. `Character == Character` runs a
	/// normalization-aware comparison that only short-circuits when the two match, so on the common
	/// miss it was the dominant cost of a scan.
	///
	/// The read is bounded by the visible width as well as by the row's own text. A buffer line
	/// can stay wider than the terminal after a resize, and those cells aren't on screen.
	func row(_ row: Int, drawsScalar scalar: UInt32, withinColumns columns: Int) -> Bool? {
		guard let text = visibleText(ofRow: row) else {
			return nil
		}

		return text.prefix(min(columns, terminalDimensions.cols)).contains {
			$0.unicodeScalars.first?.value == scalar
		}
	}

	func leadingText(ofRow row: Int, columns: Int) -> String {
		guard let text = visibleText(ofRow: row) else {
			return ""
		}

		return String(text.prefix(min(columns, terminalDimensions.cols)))
	}

	/// Copies the whole buffer, scrollback and all — SwiftTerm has no narrower read of rows outside
	/// the viewport — and keeps its last screenful. Called only while the user is scrolled back.
	func liveScreenRows() -> [String] {
		let text = String(decoding: getBufferAsData(), as: UTF8.self)
		// Every line ends in a newline, so the split leaves an empty piece after the last one.
		let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
		return lines.suffix(terminalDimensions.rows).map(String.init)
	}

	/// The row's text, or `nil` when nothing is written on it. SwiftTerm drops a row's trailing
	/// unwritten cells, so an untouched row reads as empty; a wide glyph's continuation cell is
	/// skipped, so a column count is a character count only up to the first wide glyph — the
	/// prompt sits at the start of its row, before any.
	private func visibleText(ofRow row: Int) -> String? {
		guard let text = visibleRowsText(row ..< row + 1).first, !text.isEmpty else {
			return nil
		}

		return text
	}
}
