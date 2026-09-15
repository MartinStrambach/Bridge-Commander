import AppKit
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Covers the pane end of copy-on-select: that the selection actually reaches a pasteboard, and
/// that nothing is written when the setting is off. The rules for *what* is worth copying are
/// `SelectionCopyDeciderTests`.
@Suite("Copy on select", .serialized)
@MainActor
struct CopyOnSelectTests {

	/// A pane with a real terminal buffer, no shell attached: `startProcess` is the store's job, and
	/// feeding bytes straight in is enough to have something to select.
	private func makeView(
		writingTo pasteboard: NSPasteboard,
		copyOnSelect: Bool
	) -> ClaudeAwareTerminalView {
		let view = ClaudeAwareTerminalView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			onStatusChange: { _, _ in }
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
		view.selectionPasteboard = pasteboard
		view.copiesSelectionAutomatically = copyOnSelect
		view.feed(text: "git status\r\n")

		return view
	}

	/// A pasteboard of this test's own, so a run never touches the clipboard of whoever started it.
	private func makePasteboard() -> NSPasteboard {
		let pasteboard = NSPasteboard(name: .init("BridgeCommanderCopyOnSelectTests"))
		pasteboard.clearContents()

		return pasteboard
	}

	@Test("highlighting text puts it on the pasteboard")
	func copiesTheSelection() {
		let pasteboard = makePasteboard()
		let view = makeView(writingTo: pasteboard, copyOnSelect: true)

		view.selection.setSelection(
			start: Position(col: 0, row: 0),
			// The end column is exclusive, so this is "git".
			end: Position(col: 3, row: 0)
		)
		view.copySelectionToPasteboard()

		#expect(pasteboard.string(forType: .string) == "git")
	}

	@Test("releasing the mouse over a highlight copies it")
	func copiesOnMouseUp() {
		let pasteboard = makePasteboard()
		let view = makeView(writingTo: pasteboard, copyOnSelect: true)

		view.selection.setSelection(
			start: Position(col: 0, row: 0),
			// The end column is exclusive, so this is "git".
			end: Position(col: 3, row: 0)
		)
		view.mouseUp(with: mouseUpEvent(in: view))

		#expect(pasteboard.string(forType: .string) == "git")
	}

	@Test("a pane left untouched writes nothing")
	func writesNothingWithoutASelection() {
		let pasteboard = makePasteboard()
		pasteboard.setString("something the user copied elsewhere", forType: .string)
		let view = makeView(writingTo: pasteboard, copyOnSelect: true)

		view.copySelectionToPasteboard()

		#expect(pasteboard.string(forType: .string) == "something the user copied elsewhere")
	}

	@Test("the pasteboard is left alone when the setting is off")
	func doesNotCopyWhenDisabled() {
		let pasteboard = makePasteboard()
		pasteboard.setString("something the user copied elsewhere", forType: .string)
		let view = makeView(writingTo: pasteboard, copyOnSelect: false)

		view.selection.setSelection(
			start: Position(col: 0, row: 0),
			// The end column is exclusive, so this is "git".
			end: Position(col: 3, row: 0)
		)
		view.mouseUp(with: mouseUpEvent(in: view))

		#expect(pasteboard.string(forType: .string) == "something the user copied elsewhere")
	}

	/// A release inside the pane. `mouseUp` reads the event to resolve the cell under the pointer,
	/// so it has to be a real `NSEvent` rather than a stub.
	private func mouseUpEvent(in view: NSView) -> NSEvent {
		NSEvent.mouseEvent(
			with: .leftMouseUp,
			location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			clickCount: 1,
			pressure: 0
		)!
	}
}
