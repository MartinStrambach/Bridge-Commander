/// Remembers whether the frame currently being drawn has put Claude's prompt on screen.
///
/// The grid is the better place to look for the prompt, since it says what is still visible. This
/// covers the case where the grid can't answer: while the user reads scrollback, the rows on display
/// are no longer the live screen, so the last frame drawn is the best evidence there is.
struct RenderTracker {
	private var scanner = PromptGlyphScanner()
	private var currentRenderDrewPrompt = false

	/// Set once the current render has been judged, so the next burst of output is recognised as the
	/// start of a new frame rather than a continuation of the one already reported on.
	private var renderWasJudged = false

	/// Whether the frame that ended at the last silence drew the prompt glyph.
	var drewPrompt: Bool {
		currentRenderDrewPrompt
	}

	/// Takes in a burst of output from the child process.
	mutating func received(_ bytes: some Sequence<UInt8>) {
		if renderWasJudged {
			renderWasJudged = false
			currentRenderDrewPrompt = false
		}
		if scanner.scan(bytes) {
			currentRenderDrewPrompt = true
		}
	}

	/// Records that an idle check has judged the current frame, closing it.
	mutating func markJudged() {
		renderWasJudged = true
	}
}
