import SwiftTerm

/// Reads the pane's live screen on the detector's behalf. Everything specific to the terminal
/// emulator sits here, so the heuristic itself has no opinion about how a row is stored.
extension ClaudeAwareTerminalView: PromptScreen {
	var rowCount: Int {
		terminal?.rows ?? 0
	}

	var cursorRow: Int {
		terminal?.getCursorLocation().y ?? 0
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

	/// Cells are compared by Unicode scalar value. `Character == Character` runs a
	/// normalization-aware comparison that only short-circuits when the two match, so on the common
	/// miss it was the dominant cost: measured 156 µs per scan of a 50x200 grid versus 65 µs
	/// comparing scalars.
	///
	/// The read is bounded by the visible width as well as by the row's own storage. A buffer line
	/// can stay wider than the terminal after a resize, and those cells aren't on screen.
	func row(_ row: Int, drawsScalar scalar: UInt32, withinColumns columns: Int) -> Bool? {
		guard
			let terminal,
			let line = terminal.getLine(row: row)
		else {
			return nil
		}

		let trimmedLength = line.getTrimmedLength()
		guard trimmedLength > 0 else {
			return nil // nothing written on this row
		}

		let limit = min(columns, trimmedLength, line.count, terminal.cols)
		for col in 0 ..< limit {
			if line[col].getCharacter().unicodeScalars.first?.value == scalar {
				return true
			}
		}
		return false
	}
}
