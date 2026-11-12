import AppKit
import Testing

@testable import TerminalFeature

/// Only the visible pane follows the container: every resize is a reflow and a SIGWINCH, and a
/// width change belongs to the repository on screen, not to every shell in the app.
@MainActor
@Suite("Terminal pane container")
struct TerminalPaneContainerTests {
	private let small = NSRect(x: 0, y: 0, width: 400, height: 300)
	private let large = NSRect(x: 0, y: 0, width: 800, height: 300)

	private func makeContainer(sized frame: NSRect) -> TerminalPaneContainerView {
		TerminalPaneContainerView(frame: frame)
	}

	@Test func theVisiblePaneFollowsTheContainer() {
		let container = makeContainer(sized: small)
		let pane = NSView(frame: small)
		container.addSubview(pane)

		container.frame = large
		container.layout()

		#expect(pane.frame == large)
	}

	@Test func aHiddenPaneKeepsItsSize() {
		let container = makeContainer(sized: small)
		let hidden = NSView(frame: small)
		hidden.isHidden = true
		container.addSubview(hidden)

		container.frame = large
		container.layout()

		#expect(hidden.frame == small)
	}

	/// Otherwise its shell would start at SwiftTerm's default size and reflow when first shown.
	@Test func aHiddenPaneNeverLaidOutIsSizedAnyway() {
		let container = makeContainer(sized: large)
		let hidden = NSView(frame: .zero)
		hidden.isHidden = true
		container.addSubview(hidden)

		container.layout()

		#expect(hidden.frame == large)
	}

	@Test func aPaneShownAgainTakesTheContainersCurrentSize() {
		let container = makeContainer(sized: small)
		let pane = NSView(frame: small)
		pane.isHidden = true
		container.addSubview(pane)
		container.frame = large
		container.layout()

		pane.isHidden = false
		container.layout()

		#expect(pane.frame == large)
	}
}
