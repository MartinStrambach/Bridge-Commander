import Testing

@testable import TerminalFeature

@Suite("SelectionCopyDecider")
struct SelectionCopyDeciderTests {

	@Test("a gesture that selected something copies it")
	func copiesAnActiveSelection() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == "git status")
	}

	@Test("a gesture that selected nothing leaves the pasteboard alone")
	func ignoresAnInactiveSelection() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: false, selectedText: "git status") == nil)
	}

	@Test("a selection of nothing but whitespace is not worth the clipboard")
	func ignoresWhitespace() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "   \n  ") == nil)
	}

	@Test("the same selection is not copied twice")
	func skipsARepeatOfWhatWasJustCopied() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == "git status")
		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == nil)
	}

	@Test("extending a selection copies the longer text")
	func copiesAChangedSelection() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git") == "git")
		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == "git status")
	}

	@Test("highlighting the same text again after clearing the selection copies it again")
	func copiesAgainAfterTheSelectionGoesAway() {
		var decider = SelectionCopyDecider()

		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == "git status")
		#expect(decider.textToCopy(selectionIsActive: false, selectedText: "") == nil)
		#expect(decider.textToCopy(selectionIsActive: true, selectedText: "git status") == "git status")
	}

	@Test("reading the selection is skipped when there is none")
	func doesNotReadAnInactiveSelection() {
		var decider = SelectionCopyDecider()
		var reads = 0

		_ = decider.textToCopy(
			selectionIsActive: false,
			selectedText: {
				reads += 1
				return "git status"
			}()
		)

		#expect(reads == 0)
	}
}
