import AppKit
import ComposableArchitecture
import SwiftTerm
import SwiftUI

/// An NSView container that hosts terminal panes as direct subviews and shows one of them.
///
/// The terminal panel lays its terminals out side by side, one container per pane (`slot`). The
/// first container also keeps every pane that is not on screen — other tabs', other
/// repositories' — hidden via `isHidden` rather than out of the view hierarchy, so a tab with a
/// single pane is never re-parented when tabs are switched. Panes are placed by frame, not by
/// SwiftUI, which prevents the intermediate zero-frame `setFrameSize` call that otherwise fires
/// when a view is re-parented, which would send a SIGWINCH to the shell and cause zsh to clear
/// the visible terminal output.
///
/// Only the visible pane follows the container's size (`TerminalPaneContainerView`); hidden panes
/// keep the size they last had, so a width change that belongs to one repository — its simulator
/// pane opening or closing, or a switch to a repository whose pane is in the other state — resizes
/// only the pane on screen, not every shell in the app.
public struct TerminalContainerRepresentable: NSViewRepresentable {

	public let terminalViewStore: TerminalViewStore
	public let sessions: IdentifiedArrayOf<TerminalSession>
	/// The panes on screen, left to right: one terminal, or the ones of the split.
	public let shownSessionIds: [UUID]
	/// Which of `shownSessionIds` this container shows. The container of slot 0 also keeps the
	/// sessions that are not on screen.
	public let slot: Int
	/// The pane with keyboard focus.
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
	/// A pane was clicked, and so took keyboard focus.
	public let onPaneClicked: @MainActor (UUID) -> Void

	public init(
		terminalViewStore: TerminalViewStore,
		sessions: IdentifiedArrayOf<TerminalSession>,
		shownSessionIds: [UUID],
		slot: Int = 0,
		activeSessionId: UUID?,
		colors: TerminalColors,
		readsImageFiles: Bool,
		copyOnSelect: Bool,
		mouseReporting: Bool,
		font: NSFont,
		events: TerminalPaneEvents,
		onPaneClicked: @escaping @MainActor (UUID) -> Void = { _ in }
	) {
		self.terminalViewStore = terminalViewStore
		self.sessions = sessions
		self.shownSessionIds = shownSessionIds
		self.slot = slot
		self.activeSessionId = activeSessionId
		self.colors = colors
		self.readsImageFiles = readsImageFiles
		self.copyOnSelect = copyOnSelect
		self.mouseReporting = mouseReporting
		self.font = font
		self.events = events
		self.onPaneClicked = onPaneClicked
	}

	/// Remembers which store and slot a container was made for, so it can be taken off the
	/// store's books when SwiftUI drops it.
	public final class Coordinator {
		let terminalViewStore: TerminalViewStore
		let slot: Int

		init(terminalViewStore: TerminalViewStore, slot: Int) {
			self.terminalViewStore = terminalViewStore
			self.slot = slot
		}
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator(terminalViewStore: terminalViewStore, slot: slot)
	}

	public func makeNSView(context: Context) -> NSView {
		TerminalPaneContainerView(frame: .zero)
	}

	public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
		coordinator.terminalViewStore.unregister(container: nsView, slot: coordinator.slot)
	}

	public func updateNSView(_ nsView: NSView, context: Context) {
		// Which pane goes in which container is read off the store, never off this
		// representable's own `shownSessionIds`, and only slot 0 — which is never removed —
		// writes it. SwiftUI updates a slot once more as it removes it, with the properties it
		// had: a slot going away would otherwise take back the pane it used to show, out of the
		// container that has just received it, and the terminal would leave the screen with it.
		terminalViewStore.register(container: nsView, slot: slot)
		if slot == 0 {
			terminalViewStore.shownSessionIds = shownSessionIds
		}
		let shown = terminalViewStore.shownSessionIds

		for session in sessions where session.status.isLive {
			// A pane on screen belongs to its slot's container; the rest wait in the first one.
			let shownIndex = shown.firstIndex(of: session.id)
			let targetSlot = shownIndex ?? 0
			// Slot 0 places every pane, since it is the one that learns of a new layout; another
			// slot places its own, which covers a container made after slot 0 was updated.
			guard slot == 0 || slot == targetSlot else {
				continue
			}
			guard let container = slot == targetSlot ? nsView : terminalViewStore.container(forSlot: targetSlot) else {
				continue
			}

			place(session, in: container, isShown: shownIndex != nil)
		}
	}

	private func place(_ session: TerminalSession, in container: NSView, isShown: Bool) {
		let sessionId = session.id
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
		termView.onMouseDown = { [onPaneClicked] in onPaneClicked(sessionId) }

		// Guarded on a real change, unlike the flags above: SwiftTerm's font setter
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

		if termView.superview !== container {
			// Hidden before it moves in: a pane leaving the screen keeps the size it had
			// there, and the container's layout only leaves hidden panes alone.
			if !isShown {
				termView.isHidden = true
			}
			termView.translatesAutoresizingMaskIntoConstraints = true
			termView.autoresizingMask = []
			container.addSubview(termView)
			container.needsLayout = true
		}
		if termView.isHidden == isShown {
			termView.isHidden = !isShown
			// Sized in the container's next layout, not here: this update can run before
			// SwiftUI gives the container the width of the newly shown repository, and sizing
			// to the stale bounds would resize the pane twice.
			container.needsLayout = true
		}
		if isShown, sessionId == activeSessionId {
			termView.requestFocus()
		}
		else {
			termView.cancelPendingFocus()
		}
	}

}

/// Hosts the terminal panes and sizes only the visible one to its bounds.
///
/// Every pane used to be pinned to the container's edges, so any change of the container's width
/// resized all of them — and the container's width depends on the repository on screen, whose
/// simulator pane may be open while another's is not. Each resize is a reflow and a SIGWINCH; until
/// SwiftTerm 1.99.1 a narrow→wide reflow of a Claude Code screen joined unrelated lines (see the
/// README), so switching between two repositories' tabs garbled every terminal in the app a little
/// more each time. A hidden pane keeps its size until it is shown, which for a repository's own
/// tabs is the size they will be shown at, and saves a reflow and a SIGWINCH per hidden pane.
final class TerminalPaneContainerView: NSView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		autoresizesSubviews = false
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layout() {
		super.layout()
		// Nothing fits in no room, and a pane sized to it would reflow twice.
		guard !bounds.isEmpty else {
			return
		}

		for pane in subviews where pane.frame != bounds {
			// A pane never laid out yet is sized even while hidden, so its shell does not start
			// at SwiftTerm's default size and reflow when first shown.
			if !pane.isHidden || pane.frame.isEmpty {
				pane.frame = bounds
			}
		}
	}
}
