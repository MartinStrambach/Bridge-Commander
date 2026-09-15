import Foundation

/// Decides what copy-on-select should put on the pasteboard, given the selection as it stands once
/// a mouse gesture has finished.
///
/// Split out of `ClaudeAwareTerminalView` so the rules can be checked without a terminal, a
/// pasteboard or a synthesized mouse event.
struct SelectionCopyDecider {
	/// What was copied last, so a gesture that leaves the selection untouched — a shift-click that
	/// lands where the selection already ended, a release after the drag was already copied —
	/// doesn't clear and rewrite the pasteboard for nothing.
	private var lastCopied: String?

	/// - Parameters:
	///   - selectionIsActive: Whether anything is selected at all. A gesture that selects nothing
	///     forgets `lastCopied`, so highlighting the same text again copies it again.
	///   - selectedText: The selection. An autoclosure because reading it out of the buffer is work
	///     that an inactive selection shouldn't pay for.
	/// - Returns: The text to copy, or `nil` when this gesture should leave the pasteboard alone.
	mutating func textToCopy(
		selectionIsActive: Bool,
		selectedText: @autoclosure () -> String
	) -> String? {
		guard selectionIsActive else {
			lastCopied = nil
			return nil
		}

		let text = selectedText()

		// A selection of nothing but whitespace is how an accidental drag across blank screen ends,
		// and copying it would wipe whatever the user meant to paste.
		guard
			!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			text != lastCopied
		else {
			return nil
		}

		lastCopied = text

		return text
	}
}
