import AppKit
import SwiftTerm
import Testing

@testable import TerminalFeature

/// Only the visible pane follows the container: every resize is a reflow and a SIGWINCH, and a
/// width change belongs to the repository on screen, not to every shell in the app.
@MainActor
@Suite("Terminal pane container")
struct TerminalPaneContainerTests {
	private let small = NSRect(x: 0, y: 0, width: 400, height: 300)
	private let large = NSRect(x: 0, y: 0, width: 800, height: 300)
	/// Where a pane sits in a container of the `large` size: inset by the margin on both sides.
	private let largePane = NSRect(x: 8, y: 0, width: 784, height: 300)

	private func makeContainer(sized frame: NSRect) -> TerminalPaneContainerView {
		TerminalPaneContainerView(frame: frame)
	}

	@Test func theVisiblePaneFollowsTheContainer() {
		let container = makeContainer(sized: small)
		let pane = NSView(frame: small)
		container.addSubview(pane)

		container.frame = large
		container.layout()

		#expect(pane.frame == largePane)
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

		#expect(hidden.frame == largePane)
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

		#expect(pane.frame == largePane)
	}

	/// The margin keeps the text off the panel's edges, but adds no space above or below.
	@Test func thePaneIsInsetOnlyHorizontally() {
		let container = makeContainer(sized: large)

		#expect(container.paneFrame.minX == TerminalPaneContainerView.horizontalInset)
		#expect(large.maxX - container.paneFrame.maxX == TerminalPaneContainerView.horizontalInset)
		#expect(container.paneFrame.height == large.height)
	}

	/// A container narrower than both margins gives the pane no width rather than a null frame.
	@Test func aContainerNarrowerThanItsMarginsGivesThePaneNoWidth() {
		let container = makeContainer(sized: NSRect(x: 0, y: 0, width: 10, height: 300))

		#expect(container.paneFrame == NSRect(x: 5, y: 0, width: 0, height: 300))
	}

	/// The margin is painted with the visible pane's background, so it reads as part of the pane.
	@Test func theMarginTakesTheVisiblePanesBackground() {
		// Fixed sRGB colors, so the comparison does not depend on the host's light or dark mode.
		let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
		let container = makeContainer(sized: large)
		let shown = TerminalView(frame: small)
		shown.nativeBackgroundColor = red
		let hidden = TerminalView(frame: small)
		hidden.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
		hidden.isHidden = true
		container.addSubview(hidden)
		container.addSubview(shown)

		container.layout()

		#expect(container.layer?.backgroundColor == red.cgColor)
	}
}
