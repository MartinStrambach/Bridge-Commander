import AppKit
import Foundation
import Testing

@testable import TerminalFeature

/// How a pane takes keyboard focus: at once when it is in a window, once it lands in one when it
/// is not, and never away from a control inside it (SwiftTerm's find bar).
@MainActor
@Suite("Terminal pane focus", .serialized)
struct TerminalFocusTests {
	private func makeWindow() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
			styleMask: [.titled],
			backing: .buffered,
			defer: true
		)
		window.isReleasedWhenClosed = false
		return window
	}

	private func makePane() -> TerminalPaneView {
		let view = TerminalPaneView(
			repositoryPath: "/tmp/repo",
			sessionId: UUID(),
			events: TerminalPaneEvents()
		)
		view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
		return view
	}

	/// Polls until `condition` holds, sleeping so the main queue runs the pane's deferred hop.
	private func eventually(_ condition: () -> Bool) async -> Bool {
		let clock = ContinuousClock()
		let deadline = clock.now + .seconds(2)
		while !condition(), clock.now < deadline {
			try? await Task.sleep(for: .milliseconds(20))
		}
		return condition()
	}

	@Test func aPaneInAWindowTakesFocusAtOnce() {
		let window = makeWindow()
		let pane = makePane()
		window.contentView?.addSubview(pane)

		pane.requestFocus()

		#expect(window.firstResponder === pane)
	}

	/// The terminal overlay mounts cold, so the pane is asked before SwiftUI has put it in a window.
	@Test func aPaneAskedBeforeItHasAWindowTakesFocusOnceInOne() async {
		let window = makeWindow()
		let pane = makePane()

		pane.requestFocus()
		window.contentView?.addSubview(pane)

		#expect(await eventually { window.firstResponder === pane })
	}

	@Test func aCancelledRequestIsNotTakenUpLater() async throws {
		let window = makeWindow()
		let pane = makePane()

		pane.requestFocus()
		pane.cancelPendingFocus()
		window.contentView?.addSubview(pane)
		try await Task.sleep(for: .milliseconds(100))

		#expect(window.firstResponder !== pane)
	}

	/// A field being edited is not the first responder itself — the window's field editor is, with
	/// the field as its delegate. Taking focus anyway once sent ⌘F's search text to the shell.
	@Test func focusInsideThePaneIsLeftWhereItIs() throws {
		let window = makeWindow()
		let pane = makePane()
		window.contentView?.addSubview(pane)
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
		pane.addSubview(field)
		try #require(window.makeFirstResponder(field))
		let editor = window.firstResponder

		pane.requestFocus()

		#expect(window.firstResponder === editor)
		#expect((window.firstResponder as? NSTextView)?.delegate === field)
	}

	@Test func focusElsewhereInTheWindowIsTaken() throws {
		let window = makeWindow()
		let pane = makePane()
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
		window.contentView?.addSubview(field)
		window.contentView?.addSubview(pane)
		try #require(window.makeFirstResponder(field))

		pane.requestFocus()

		#expect(window.firstResponder === pane)
	}
}
