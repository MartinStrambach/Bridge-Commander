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

	// MARK: - Coordinator

	/// Owns strong references to per-session TerminalProcessDelegate instances.
	/// SwiftUI manages the coordinator's lifetime — it lives as long as the representable
	/// is in the view hierarchy, ensuring delegates are released when the terminal panel closes.
	public final class Coordinator {
		public var processDelegates: [UUID: TerminalProcessDelegate] = [:]
	}

	public let terminalViewStore: TerminalViewStore
	public let sessions: IdentifiedArrayOf<TerminalSession>
	public let activeSessionId: UUID?
	public let foregroundColor: NSColor
	public let backgroundColor: NSColor
	/// The 16 ANSI colors of an imported profile, or `nil` for SwiftTerm's default palette.
	public let ansiPalette: [NSColor]?
	/// An imported profile's caret color, or `nil` for SwiftTerm's default.
	public let cursorColor: NSColor?
	/// An imported profile's selection background, or `nil` for SwiftTerm's default.
	public let selectionColor: NSColor?
	public let copyOnSelect: Bool
	public let mouseReporting: Bool
	/// What new panes base their waiting/active status on. Unlike the flags beside it, a pane
	/// keeps the source it was created with — see `ClaudeStatusSource`.
	public let statusSource: ClaudeStatusSource
	/// The font every pane renders with. Resolved by the caller — the family and its point size are
	/// both settings, and this package stays free of a Settings dependency.
	public let font: NSFont
	public let onStatusChange: @Sendable (UUID, TerminalSessionStatus) -> Void
	public let onNotification: @Sendable (UUID, TerminalNotification) -> Void
	/// A ⌘-clicked link that names a file.
	public let onOpenFile: @Sendable (UUID, TerminalFileLink) -> Void

	public init(
		terminalViewStore: TerminalViewStore,
		sessions: IdentifiedArrayOf<TerminalSession>,
		activeSessionId: UUID?,
		foregroundColor: NSColor,
		backgroundColor: NSColor,
		ansiPalette: [NSColor]? = nil,
		cursorColor: NSColor? = nil,
		selectionColor: NSColor? = nil,
		copyOnSelect: Bool,
		mouseReporting: Bool,
		statusSource: ClaudeStatusSource = .progressAndScreen,
		font: NSFont,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void,
		onNotification: @escaping @Sendable (UUID, TerminalNotification) -> Void,
		onOpenFile: @escaping @Sendable (UUID, TerminalFileLink) -> Void
	) {
		self.terminalViewStore = terminalViewStore
		self.sessions = sessions
		self.activeSessionId = activeSessionId
		self.foregroundColor = foregroundColor
		self.backgroundColor = backgroundColor
		self.ansiPalette = ansiPalette
		self.cursorColor = cursorColor
		self.selectionColor = selectionColor
		self.copyOnSelect = copyOnSelect
		self.mouseReporting = mouseReporting
		self.statusSource = statusSource
		self.font = font
		self.onStatusChange = onStatusChange
		self.onNotification = onNotification
		self.onOpenFile = onOpenFile
	}

	public func makeNSView(context: Context) -> NSView {
		TerminalPaneContainerView(frame: .zero)
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator()
	}

	public func updateNSView(_ nsView: NSView, context: Context) {
		for session in sessions {
			switch session.status {
			case .active,
			     .launching,
			     .waitingForInput:
				let sessionId = session.id

				// Retrieve or create the process delegate, held strongly by the coordinator.
				// LocalProcessTerminalView.processDelegate is a weak var, so the coordinator
				// must own the strong reference for callbacks to fire.
				let delegate: TerminalProcessDelegate
				if let existing = context.coordinator.processDelegates[sessionId] {
					delegate = existing
				}
				else {
					let newDelegate = TerminalProcessDelegate(
						onFailed: { message in onStatusChange(sessionId, .failed(message)) }
					)
					context.coordinator.processDelegates[sessionId] = newDelegate
					delegate = newDelegate
				}

				let termView = terminalViewStore.view(
					for: session,
					foregroundColor: foregroundColor,
					backgroundColor: backgroundColor,
					ansiPalette: ansiPalette,
					cursorColor: cursorColor,
					selectionColor: selectionColor,
					statusSource: statusSource,
					processDelegate: delegate,
					onStatusChange: onStatusChange,
					onNotification: onNotification,
					onOpenFile: onOpenFile
				)
				// Assigned on every update, not at creation: panes outlive a change to the
				// setting, and the colors only look like they don't because a new theme is
				// documented as applying to newly opened terminals.
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

			case .failed:
				break
			}
		}

		// Release delegates for sessions that are no longer present (killed or failed).
		let activeIds = Set(sessions.map(\.id))
		context.coordinator.processDelegates = context.coordinator
			.processDelegates
			.filter { activeIds.contains($0.key) }
	}

}

/// Hosts the terminal panes and sizes only the visible one to its bounds.
///
/// Every pane used to be pinned to the container's edges, so any change of the container's width
/// resized all of them — and the container's width depends on the repository on screen, whose
/// simulator pane may be open while another's is not. Each resize is a reflow and a SIGWINCH; a
/// narrow→wide reflow of a Claude Code screen joins unrelated lines (SwiftTerm keeps stale soft-wrap
/// flags, see the README), so switching between two repositories' tabs garbled every terminal
/// in the app a little more each time. A hidden pane now keeps its size until it is shown, which
/// for a repository's own tabs is the size they will be shown at.
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
		for pane in subviews where pane.frame != bounds {
			// A pane never laid out yet is sized even while hidden, so its shell does not start
			// at SwiftTerm's default size and reflow when first shown.
			if !pane.isHidden || pane.frame.isEmpty {
				pane.frame = bounds
			}
		}
	}
}
