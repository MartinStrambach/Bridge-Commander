import AppKit
import ComposableArchitecture
import SwiftTerm
import SwiftUI

/// A single NSView container that hosts all terminal sessions as direct subviews.
///
/// All `LocalProcessTerminalView` instances live inside this one container and
/// are shown/hidden via `isHidden` rather than being added to and removed from
/// the view hierarchy. This prevents the intermediate zero-frame `setFrameSize`
/// call that otherwise fires when a view is re-parented, which would send a
/// SIGWINCH to the shell and cause zsh to clear the visible terminal output.
///
/// Only the visible pane follows the container's size (`TerminalPaneContainerView`); hidden panes
/// keep the size they last had, so a width change that belongs to one repository — its simulator
/// pane opening or closing, or a switch to a repository whose pane is in the other state — resizes
/// only the pane on screen, not every shell in the app.
public struct TerminalContainerRepresentable: NSViewRepresentable {

	public let terminalViewStore: TerminalViewStore
	public let sessions: IdentifiedArrayOf<TerminalSession>
	public let activeSessionId: UUID?
	/// The colors a new pane is created with.
	public let colors: TerminalColors
	/// Whether a new pane loads Kitty graphics images from files a program names.
	public let readsImageFiles: Bool
	public let copyOnSelect: Bool
	public let mouseReporting: Bool
	/// The font every pane renders with. Resolved by the caller — the family and its point size are
	/// both settings, and this package stays free of a Settings dependency.
	public let font: NSFont
	/// What a new pane reports.
	public let events: TerminalPaneEvents

	public init(
		terminalViewStore: TerminalViewStore,
		sessions: IdentifiedArrayOf<TerminalSession>,
		activeSessionId: UUID?,
		colors: TerminalColors,
		readsImageFiles: Bool,
		copyOnSelect: Bool,
		mouseReporting: Bool,
		font: NSFont,
		events: TerminalPaneEvents
	) {
		self.terminalViewStore = terminalViewStore
		self.sessions = sessions
		self.activeSessionId = activeSessionId
		self.colors = colors
		self.readsImageFiles = readsImageFiles
		self.copyOnSelect = copyOnSelect
		self.mouseReporting = mouseReporting
		self.font = font
		self.events = events
	}

	public func makeNSView(context: Context) -> NSView {
		TerminalPaneContainerView(frame: .zero)
	}

	public func updateNSView(_ nsView: NSView, context: Context) {
		for session in sessions where session.status.isLive {
			let termView = terminalViewStore.view(
				for: session,
				colors: colors,
				readsImageFiles: readsImageFiles,
				events: events
			)
			// Assigned on every update, not at creation: panes outlive a change to the
			// setting, and the colors and image file permission only look like they don't
			// because both are documented as applying to newly opened terminals.
			termView.copiesSelectionAutomatically = copyOnSelect
			termView.allowMouseReporting = mouseReporting

			// Guarded on a real change, unlike the two flags above: SwiftTerm's font setter
			// rebuilds the bold/italic faces, drops the selection and re-derives the column and
			// row count from the new cell size, which resizes the PTY and sends the shell a
			// SIGWINCH. That is the right thing to do when the user picks a font, and the wrong
			// thing to do on every unrelated update pass. Compared by name and size rather than
			// with `!=`: NSFont equality also weighs matrix and descriptor attributes that the
			// view may have derived, which would make the guard fire every pass.
			if
				termView.font.fontName != font.fontName
				|| termView.font.pointSize != font.pointSize
			{
				termView.font = font
			}

			if termView.superview !== nsView {
				termView.translatesAutoresizingMaskIntoConstraints = true
				termView.autoresizingMask = []
				nsView.addSubview(termView)
				nsView.needsLayout = true
			}
			let isActive = session.id == activeSessionId
			if termView.isHidden == isActive {
				termView.isHidden = !isActive
				// Sized in the container's next layout, not here: this update can run before
				// SwiftUI gives the container the width of the newly shown repository, and sizing
				// to the stale bounds would resize the pane twice.
				nsView.needsLayout = true
			}
			if isActive {
				termView.requestFocus()
			}
			else {
				termView.cancelPendingFocus()
			}
		}
	}

}

/// Hosts the terminal panes and sizes only the visible one to its bounds, less a horizontal margin.
///
/// Every pane used to be pinned to the container's edges, so any change of the container's width
/// resized all of them — and the container's width depends on the repository on screen, whose
/// simulator pane may be open while another's is not. Each resize is a reflow and a SIGWINCH; until
/// SwiftTerm 1.99.1 a narrow→wide reflow of a Claude Code screen joined unrelated lines (see the
/// README), so switching between two repositories' tabs garbled every terminal in the app a little
/// more each time. A hidden pane keeps its size until it is shown, which for a repository's own
/// tabs is the size they will be shown at, and saves a reflow and a SIGWINCH per hidden pane.
///
/// The margin keeps text off the panel's edges. SwiftTerm used to leave a scroller's width free at
/// the right; since 1.99 it reserves none while its own `scrollerStyle` is `.overlay`, its default,
/// so the columns would run to the edge. The margin is painted in the visible pane's background
/// color, so it reads as part of it.
final class TerminalPaneContainerView: NSView {
	/// Space left free on each side of the visible pane, in points.
	static let horizontalInset: CGFloat = 8

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		autoresizesSubviews = false
		wantsLayer = true
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	/// The frame the visible pane takes: the bounds less the horizontal margin.
	var paneFrame: NSRect {
		bounds.insetBy(dx: min(Self.horizontalInset, bounds.width / 2), dy: 0)
	}

	override func layout() {
		super.layout()
		let paneFrame = paneFrame
		for pane in subviews where pane.frame != paneFrame {
			// A pane never laid out yet is sized even while hidden, so its shell does not start
			// at SwiftTerm's default size and reflow when first shown.
			if !pane.isHidden || pane.frame.isEmpty {
				pane.frame = paneFrame
			}
		}
		paintMargin()
	}

	override func viewDidChangeEffectiveAppearance() {
		super.viewDidChangeEffectiveAppearance()
		paintMargin()
	}

	/// Fills the container, and with it the margin, with the visible pane's background. Each pane
	/// keeps the colors it was created with, so the color follows whichever pane is shown; showing
	/// another pane lays the container out again.
	private func paintMargin() {
		let visiblePane = subviews.first { !$0.isHidden } as? TerminalView
		effectiveAppearance.performAsCurrentDrawingAppearance {
			layer?.backgroundColor = visiblePane?.nativeBackgroundColor.cgColor
		}
	}
}
