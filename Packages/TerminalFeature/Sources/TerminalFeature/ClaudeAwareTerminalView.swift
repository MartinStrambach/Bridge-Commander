import AppKit
import Foundation
import SwiftTerm
import Synchronization

/// A terminal pane that reports whether the program in it — Claude Code, or anything else that
/// reports its status — is waiting for the user, and knows the Claude conversation it runs.
///
/// The judgement lives in `ProgramStatusDetector`. This type owns the pane and forwards it what
/// the program reports (OSC 7501) and when output arrives. Notifications the program asks for go
/// straight up to the session.
public final class ClaudeAwareTerminalView: LocalProcessTerminalView {
	public let repositoryPath: String
	public let sessionId: UUID

	private let onStatusChange: @Sendable (UUID, TerminalSessionStatus, TerminalProgramReport?) -> Void
	private let onNotification: @Sendable (UUID, TerminalNotification) -> Void

	/// Built on first use, since it reads this view's process and `self` isn't available until
	/// `super.init` has run.
	private lazy var detector = ProgramStatusDetector(
		label: repositoryPath,
		isShellInForeground: { [weak self] in
			guard let process = self?.process else {
				return nil
			}

			return PtyForegroundProcess.isInForeground(processGroup: process.shellPid, ptyDescriptor: process.childfd)
		},
		onStatusChange: { [weak self] status, report in
			guard let self else {
				return
			}

			onStatusChange(sessionId, status, report)
		}
	)

	public init(
		repositoryPath: String,
		sessionId: UUID,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus, TerminalProgramReport?) -> Void,
		onNotification: @escaping @Sendable (UUID, TerminalNotification) -> Void
	) {
		self.repositoryPath = repositoryPath
		self.sessionId = sessionId
		self.onStatusChange = onStatusChange
		self.onNotification = onNotification
		super.init(frame: .zero)
		cellGridScale = Self.currentBackingScale(of: nil)
		registerForDraggedTypes([.fileURL])
		observeNotifications()
		observeProcessOutput()
	}

	/// Unsupported: a pane is only ever built in code, for the session it belongs to.
	public required init?(coder: NSCoder) {
		nil
	}

	/// A pane that goes away for any reason takes its shell with it. `TerminalViewStore` hangs up
	/// explicitly when it kills a session; this covers the store itself being released, as it is
	/// when the window closes.
	isolated deinit {
		hangUp()
		if let wordMotionMonitor {
			NSEvent.removeMonitor(wordMotionMonitor)
		}
	}

	// MARK: - Backing scale

	/// The pixels-per-point the cell grid was last measured for.
	///
	/// SwiftTerm snaps the cell width and height to the pixel grid of whichever screen the pane is
	/// on when the font is set (`computeFontDimensions`), and only re-measures when the font is set
	/// again. It never reacts to the pane moving to a screen with a different backing scale, so
	/// after unplugging an external monitor a grid snapped for one scale is drawn at another: cell
	/// edges fall between pixels, glyphs smear into their neighbours and the column count no longer
	/// matches the width. Set from the same fallback chain SwiftTerm uses, since a pane is built
	/// before it has a window and measures against the main screen.
	private var cellGridScale: CGFloat = 1

	private static func currentBackingScale(of window: NSWindow?) -> CGFloat {
		window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
	}

	override public func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()
		remeasureCellGridIfScaleChanged()
	}

	/// Also checked here: the first measurement happened against the main screen, and the window
	/// the pane is added to may sit on a different one.
	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		remeasureCellGridIfScaleChanged()
		updateWordMotionMonitor()
		takePendingFocus()
	}

	/// Re-snaps the cell grid to the current screen when its scale differs from the one the grid
	/// was measured for.
	///
	/// Goes through the public `font` setter, the only entry to SwiftTerm's `resetFont`: it
	/// recomputes the cell size, resizes the terminal to the columns and rows that now fit, and
	/// drops the selection. That resize reaches the shell as a SIGWINCH, which is the right outcome
	/// here — the number of cells that fit really did change — and is why this runs only on an
	/// actual scale change, not on every backing-properties callback (a color space change fires
	/// it too). A pane without a window keeps its grid: the window's scale is the only one that
	/// matters, and there is none to compare against.
	private func remeasureCellGridIfScaleChanged() {
		guard let window else {
			return
		}

		let scale = Self.currentBackingScale(of: window)
		guard scale != cellGridScale else {
			return
		}

		cellGridScale = scale
		font = font
	}

	// MARK: - Word motion

	/// Watches for ⌥← / ⌥→ while the pane is in a window; see `OptionArrowWordMotion` for why.
	///
	/// A local event monitor rather than an override: SwiftTerm declares `keyDown` `public`, not
	/// `open`, so a subclass outside its module cannot intercept the key there.
	private var wordMotionMonitor: Any?

	private func updateWordMotionMonitor() {
		if let wordMotionMonitor {
			NSEvent.removeMonitor(wordMotionMonitor)
			self.wordMotionMonitor = nil
		}
		guard window != nil else {
			return
		}

		wordMotionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard
				let self,
				let window,
				event.window === window,
				window.firstResponder === self,
				let bytes = OptionArrowWordMotion.bytes(
					modifiers: event.modifierFlags,
					charactersIgnoringModifiers: event.charactersIgnoringModifiers,
					optionIsMeta: optionAsMetaKey,
					kittyProtocolActive: !keyboardEnhancementFlags.isEmpty
				)
			else {
				return event
			}

			send(bytes)
			return nil
		}
	}

	// MARK: - Notifications

	/// Keeps the OSC observation below alive for as long as the pane.
	private var oscObservation: TerminalOscObservation?

	/// Handles OSC 9 and OSC 777 the way Ghostty does. SwiftTerm parses OSC 777 but hands it to a
	/// delegate method its Mac view never implements, and treats OSC 9 as a progress report only,
	/// so both are watched here. The observation is passive — SwiftTerm still handles every
	/// sequence itself, so a `9;4` progress report still reaches its progress bar — and its events
	/// arrive on a private serial queue, in the order they were parsed.
	private func observeNotifications() {
		oscObservation = observeOscEvents { [weak self] event in
			guard event.code == 9 || event.code == 777 else {
				return
			}

			DispatchQueue.main.async {
				self?.oscEventReceived(code: event.code, payload: event.payload[...])
			}
		}
	}

	private func oscEventReceived(code: Int, payload: ArraySlice<UInt8>) {
		if code == 777 {
			if let notification = TerminalNotification(osc777: payload) {
				notificationReceived(notification)
			}
			return
		}

		if case let .notification(notification) = OSC9Payload(payload) {
			notificationReceived(notification)
		}
	}

	/// OSC 7501 reports, as SwiftTerm stores them: all of the pane's current records, on the main
	/// thread, possibly several updates folded into one call. SwiftTerm answers a program's
	/// `OSC 7501 ; ?` probe itself, which is what makes Claude Code report at all.
	override public func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
		super.programStatusChanged(source: source, records: records)
		detector.statusReported(TerminalProgramReport(records: records))
	}

	/// Passes a notification up, unless the pane's session is being killed, marked with whether the
	/// program reports its status. The pane's status is left to the program's reports: a
	/// notification alone does not say the program is waiting.
	private func notificationReceived(_ notification: TerminalNotification) {
		guard !detector.isStopped else {
			return
		}

		var notification = notification
		notification.isFromStatusReportingProgram = detector.isReportStanding

		onNotification(sessionId, notification)
	}

	// MARK: - Focus

	/// Set when the pane was asked to take keyboard focus before it had a window to take it in.
	private var wantsFocusOnceInWindow = false

	/// Makes this pane the window's first responder, now if it is in a window, otherwise as soon
	/// as it lands in one.
	///
	/// Opening a terminal from the repository list mounts the whole terminal overlay cold, so the
	/// representable's first update adds the pane to a container that SwiftUI has not put in the
	/// window yet — and it is not there one run loop later either, which is all a single deferred
	/// `makeFirstResponder` waited for. Nothing asked again afterwards, so the new terminal came up
	/// without the caret until clicked. Waiting for `viewDidMoveToWindow` needs no guess at when.
	///
	/// Focus already inside the pane is left where it is. The representable asks on every update
	/// pass, and a Claude status change is one, so taking focus unconditionally pulled it out of
	/// SwiftTerm's find bar a moment after ⌘F opened it, and the search text went to the shell.
	public func requestFocus() {
		if let window {
			wantsFocusOnceInWindow = false
			if !holdsFocus(in: window) {
				window.makeFirstResponder(self)
			}
		}
		else {
			wantsFocusOnceInWindow = true
		}
	}

	/// Whether the window's first responder is this pane or a control inside it. A text field
	/// being edited is not itself the first responder: the window's shared field editor is, with
	/// the field as its delegate.
	private func holdsFocus(in window: NSWindow) -> Bool {
		var responder = window.firstResponder
		if let editor = responder as? NSTextView, editor.isFieldEditor {
			responder = editor.delegate as? NSView
		}
		guard let view = responder as? NSView else {
			return false
		}

		return view.isDescendant(of: self)
	}

	/// Drops a focus request that has not been met yet, for a pane that stopped being the active
	/// one before it reached a window.
	public func cancelPendingFocus() {
		wantsFocusOnceInWindow = false
	}

	/// Deferred one turn: SwiftUI is still inserting the hosting hierarchy when this fires, and a
	/// first responder set in the middle of that can be reset by the insertion finishing.
	private func takePendingFocus() {
		guard wantsFocusOnceInWindow, window != nil else {
			return
		}

		DispatchQueue.main.async { [weak self] in
			guard let self, wantsFocusOnceInWindow, let window, !isHidden else {
				return
			}

			wantsFocusOnceInWindow = false
			window.makeFirstResponder(self)
		}
	}

	/// Stops the pane reporting Claude's status. Called when its session is killed, before the
	/// shell is hung up: the exit writes a last frame, and the session it would be judged for is
	/// already gone. Left running, that judgement could land after the terminal panel has closed.
	public func stopReportingStatus() {
		detector.stop()
	}

	/// Ends the shell the way closing a terminal window does: it gets SIGHUP, exits, and passes the
	/// signal on to its jobs, so a Claude Code session running in the pane goes down with it.
	///
	/// Dropping the view is not enough on its own. SwiftTerm closes its I/O channel without
	/// stopping the read that is always pending on the pseudo-terminal, so the master side stays
	/// open and no hangup ever reaches the shell; a killed pane left zsh and Claude running until
	/// the app quit. SwiftTerm's own `terminate()` would not do either, since it sends SIGTERM and
	/// interactive zsh ignores that.
	///
	/// Safe to call more than once and after the shell has already exited: `running` goes false
	/// as soon as SwiftTerm reaps the child, and a pid that was never assigned is refused so the
	/// signal can never go to this process's own group.
	public func hangUp() {
		guard let process, process.running, process.shellPid > 0 else {
			return
		}

		kill(process.shellPid, SIGHUP)
	}

	/// The directory the pane's shell is in now, or `nil` once it has exited.
	public var currentDirectory: String? {
		guard let process, process.running else {
			return nil
		}

		return ProcessWorkingDirectory.of(processId: process.shellPid)
	}

	/// The Claude Code conversation in the pane's foreground, or `nil` when Claude is not running
	/// there.
	public var claudeSessionId: String? {
		guard let process, process.running else {
			return nil
		}

		return ClaudeSession.id(inForegroundOf: process.childfd)
	}

	/// Whether highlighting text with the mouse copies it to the pasteboard without a ⌘C.
	///
	/// Off unless the user turns it on in Settings: every highlight replaces whatever they copied
	/// elsewhere, which is a surprise for anyone who selects text just to read it. The pane is
	/// reused across changes to the setting, so this is a var the view layer keeps in sync rather
	/// than an init parameter.
	public var copiesSelectionAutomatically = false

	/// Where copy-on-select writes. The general pasteboard in the app; tests hand it a private one
	/// so they don't clobber the clipboard of whoever is running them.
	var selectionPasteboard: NSPasteboard = .general

	/// Holds the rules for what a finished gesture is worth copying.
	private var copyDecider = SelectionCopyDecider()

	/// Copies whatever the mouse just highlighted, the way X11 and most terminal emulators do.
	///
	/// This runs after `super`, since SwiftTerm finishes the gesture there: the drag's last extension
	/// lands in `mouseDragged`, and word/line selection for a double or triple click in `mouseDown`.
	/// The overridden method has early returns (an opened link, a mouse-reporting app swallowing the
	/// release), but none of them leave a new selection behind, so reading it here is enough.
	override public func mouseUp(with event: NSEvent) {
		super.mouseUp(with: event)

		guard copiesSelectionAutomatically else {
			return
		}

		copySelectionToPasteboard()
	}

	/// Puts the current selection on the pasteboard, if `SelectionCopyDecider` judges there is one
	/// worth copying. Internal so a test can drive it without synthesizing a mouse event.
	func copySelectionToPasteboard() {
		// `nil` while no selection is active.
		let selectedText = getSelection()
		guard
			let text = copyDecider.textToCopy(
				selectionIsActive: selectedText != nil,
				selectedText: selectedText ?? ""
			)
		else {
			return
		}

		selectionPasteboard.clearContents()
		selectionPasteboard.setString(text, forType: .string)
	}

	/// A command to type into the shell, held until the shell first writes something.
	///
	/// Sent on first output rather than straight after launch: bytes written before the shell has
	/// its line editor up are echoed by the tty as raw typeahead, and then echoed again by the
	/// line editor at the prompt, so the command would show twice. The first output is usually
	/// the prompt; a startup file that prints something first costs at most that stray echo.
	var pendingStartupCommand: String?

	/// Has the main thread told about the child's output.
	///
	/// SwiftTerm parses the child's output on its IO thread and calls the handler there after
	/// each batch, with no bytes (since 1.99 `dataReceived(slice:)` is no longer called). A burst
	/// of output is many batches, so a hop already queued is not queued again.
	private func observeProcessOutput() {
		let hop = PendingMainHop()
		setProcessOutputHandler { [weak self] in
			guard hop.claim() else {
				return
			}

			DispatchQueue.main.async {
				hop.release()
				self?.processOutputReceived()
			}
		}
	}

	/// Internal so a test can stand in for the child writing output, which it cannot do once killed.
	func processOutputReceived() {
		detector.outputReceived()
		if let command = pendingStartupCommand {
			pendingStartupCommand = nil
			send(txt: command + "\r")
		}
	}
}

/// Whether a hop to the main thread is already queued, claimed from SwiftTerm's IO thread and
/// released on the main thread. Internal for its tests.
final class PendingMainHop: Sendable {
	private let isPending = Atomic(false)

	/// Whether the caller should queue the hop: `false` while one is already queued.
	func claim() -> Bool {
		isPending.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged
	}

	/// Released before the hop does its work, so output that arrives meanwhile queues another.
	func release() {
		isPending.store(false, ordering: .releasing)
	}
}
