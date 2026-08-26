import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
public final class TerminalViewStore {
	private var views: [UUID: ClaudeAwareTerminalView] = [:]

	public init() {}

	/// Returns the existing terminal view for a session, or creates and starts a new one.
	/// The caller is responsible for creating `processDelegate` and keeping a strong reference
	/// to it (e.g. in an NSViewRepresentable Coordinator).
	public func view(
		for session: TerminalSession,
		foregroundColor: NSColor,
		backgroundColor: NSColor,
		processDelegate: TerminalProcessDelegate,
		onStatusChange: @escaping @Sendable (UUID, TerminalSessionStatus) -> Void
	) -> ClaudeAwareTerminalView {
		if let existing = views[session.id] {
			return existing
		}

		let terminalView = ClaudeAwareTerminalView(frame: .zero)
		terminalView.repositoryPath = session.repositoryPath
		terminalView.sessionId = session.id
		terminalView.onStatusChange = onStatusChange
		// Default to AltGr mode so European keyboards (e.g. Czech Option+4 = $) work correctly.
		// Users can toggle back to Meta mode with Option+Command+O if needed.
		terminalView.optionAsMetaKey = false

		terminalView.nativeForegroundColor = foregroundColor
		terminalView.nativeBackgroundColor = backgroundColor
		terminalView.allowMouseReporting = false
		terminalView.terminal.changeHistorySize(3000)

		terminalView.processDelegate = processDelegate

		terminalView.startProcess(
			executable: "/bin/zsh",
			args: ["-l"],
			environment: nil,
			execName: nil,
			currentDirectory: session.startingDirectory
		)

		// Store the view before calling onStatusChange to prevent re-entrancy:
		// onStatusChange triggers a TCA state mutation that can cause updateNSView to fire
		// again synchronously; if views[id] were still nil at that point, a second
		// ClaudeAwareTerminalView would be created for the same session.
		views[session.id] = terminalView

		onStatusChange(session.id, .active)

		return terminalView
	}

	public func removeSession(sessionId: UUID) {
		views.removeValue(forKey: sessionId)
	}

	public func killSession(sessionId: UUID) {
		if let view = views[sessionId] {
			view.processDelegate = nil // prevent spurious .failed callback
			view.removeFromSuperview() // remove from NSView container
		}
		views.removeValue(forKey: sessionId)
		// Process gets SIGHUP when PTY closes on deallocation
	}

	public func killAllSessions(for repositoryPath: String) {
		let sessionIds = views.compactMap { id, view -> UUID? in
			view.repositoryPath == repositoryPath ? id : nil
		}
		for id in sessionIds {
			killSession(sessionId: id)
		}
	}

	public func killAll() {
		// Removing references lets ARC release LocalProcessTerminalView instances,
		// whose deinit cleans up the underlying PTY. The OS also reclaims child
		// processes when the app exits.
		views.removeAll()
	}
}

// MARK: - ClaudeAwareTerminalView

/// Subclass of LocalProcessTerminalView that monitors terminal content for the
/// Claude Code waiting-for-input prompt (❯, U+276F) and reports status changes.
///
/// The signal is silence from the process, qualified by the prompt being on screen. Since a waiting
/// session writes nothing, every path that reports `.active` has to arrange for its own re-check —
/// otherwise the status stays where the last event left it for as long as Claude stays quiet.
public final class ClaudeAwareTerminalView: LocalProcessTerminalView {
	private static let claudePromptScalar: UInt32 = 0x276F // ❯

	/// Claude draws its input prompt at column 0 and the arrow of a selected option at column 1.
	/// The bound leaves room for small layout changes while rejecting the glyph where it can only be
	/// ordinary output — mid-line in a diff, a log message, or a file being printed.
	private static let maxPromptColumn = 4

	/// Both prompt shapes sit on the last rendered lines, so the walk gives up after this many
	/// non-empty rows. A `❯` further up the screen is scrollback, not a live prompt.
	private static let maxInspectedRows = 12

	public var repositoryPath: String = ""
	public var sessionId: UUID = .init()
	public var onStatusChange: (@Sendable (UUID, TerminalSessionStatus) -> Void)?

	private var currentStatus: TerminalSessionStatus = .active
	private var debounceWorkItem: DispatchWorkItem?

	/// Whether the render that ended at the last silence drew the prompt glyph. Read when the grid
	/// itself can't be trusted because the user has scrolled the live screen out of view.
	private var lastRenderDrewPrompt = false

	/// Set once an idle check runs, so the next burst of output is recognised as the start of a new
	/// render rather than a continuation of the one already judged.
	private var idleCheckDidRun = false

	private var promptGlyphScanner = PromptGlyphScanner()

	// MARK: - Init

	override public init(frame: NSRect) {
		super.init(frame: frame)
		registerForDraggedTypes([.fileURL])
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		registerForDraggedTypes([.fileURL])
	}

	// MARK: - Drag & Drop

	override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
			? .copy
			: []
	}

	override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let pb = sender.draggingPasteboard
		guard
			let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
			!urls.isEmpty
		else {
			return false
		}

		let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
		guard let bytes = paths.data(using: .utf8) else {
			return false
		}

		send(source: self, data: ArraySlice(bytes))
		return true
	}

	// MARK: - Data-flow based detection

	/// Called by LocalProcess whenever the child process writes bytes to the terminal.
	/// We use the silence between writes as the signal: if no data arrives for
	/// `idleThreshold` seconds AND the Claude prompt character is visible,
	/// the session is waiting for user input.
	override public func dataReceived(slice: ArraySlice<UInt8>) {
		super.dataReceived(slice: slice)

		// A burst that follows an idle check opens a new render window: whatever the previous one
		// drew has been judged already and may no longer be on screen.
		if idleCheckDidRun {
			idleCheckDidRun = false
			lastRenderDrewPrompt = false
		}
		if promptGlyphScanner.scan(slice) {
			lastRenderDrewPrompt = true
		}

		// Data is flowing → Claude is working, not waiting.
		if currentStatus == .waitingForInput {
			reportStatus(.active)
		}
		scheduleIdleCheck()
	}

	/// Called when the user sends keystrokes to the process.
	override public func send(source: TerminalView, data: ArraySlice<UInt8>) {
		super.send(source: source, data: data)
		if currentStatus == .waitingForInput {
			reportStatus(.active)
		}
		// Keystrokes are the other way into `.active`, so they have to re-arm the check too. A key
		// that Claude doesn't echo produces no output, and without this the session would sit on a
		// stale `.active` until it wrote something again.
		scheduleIdleCheck()
	}

	private func scheduleIdleCheck() {
		debounceWorkItem?.cancel()
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else {
				return
			}

			checkIfWaiting()
		}
		debounceWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
	}

	/// After 1.5 s of silence from the process, check whether Claude is sitting at a prompt — its
	/// input box, or the arrow marking the selected option of a dialog.
	///
	/// The glyph alone is weak evidence, so it is qualified twice over: the pane must have Claude in
	/// the foreground, and the hit must land where Claude puts a prompt rather than anywhere on
	/// screen.
	///
	/// Runs on the main thread after every burst of output, for every open session, so the scan
	/// is kept off the slow paths:
	/// - Panes that aren't running Claude skip the grid walk altogether.
	/// - Rows are walked bottom-up and only the leftmost columns of each are read. The prompt sits on
	///   the last written line, so a hit exits almost immediately instead of after a full grid
	///   traversal.
	/// - Only the trimmed length of each row is read; untouched cells can't hold the prompt, and
	///   blank rows below the cursor cost nothing.
	/// - Cells are compared by Unicode scalar value. `Character == Character` runs a
	///   normalization-aware comparison that only short-circuits when the two match, so on the
	///   common miss it was the dominant cost: measured 156 µs per scan of a 50x200 grid
	///   versus 65 µs comparing scalars.
	private func checkIfWaiting() {
		idleCheckDidRun = true

		guard let t = terminal else {
			return
		}

		// A shell prompt theme, a diff, or scrollback can all put `❯` on screen, so the glyph only
		// carries meaning while Claude owns the pane. An unidentifiable foreground process falls
		// through to the scan.
		if PtyForegroundProcess.isClaude(ptyDescriptor: process?.childfd ?? -1) == false {
			reportStatus(.active)
			return
		}

		// `Terminal.getLine(row:)` is relative to the scroll position, so a user reading back through
		// scrollback would have the prompt scanned for on a screen that no longer holds it. Judge the
		// render itself in that case: the last frame Claude drew before going quiet is what the live
		// screen still shows.
		guard isShowingLiveScreen else {
			reportStatus(lastRenderDrewPrompt ? .waitingForInput : .active)
			return
		}

		var inspectedRows = 0
		for row in stride(from: t.rows - 1, through: 0, by: -1) {
			guard let line = t.getLine(row: row) else {
				continue
			}

			// Bounded by the visible width as well as the row's own storage: a buffer line can
			// stay wider than the terminal after a resize, and those cells aren't on screen.
			let trimmedLength = line.getTrimmedLength()
			guard trimmedLength > 0 else {
				continue
			}

			let limit = min(trimmedLength, line.count, t.cols, Self.maxPromptColumn + 1)
			for col in 0 ..< limit {
				if line[col].getCharacter().unicodeScalars.first?.value == Self.claudePromptScalar {
					reportStatus(.waitingForInput)
					return
				}
			}

			inspectedRows += 1
			if inspectedRows == Self.maxInspectedRows {
				break
			}
		}
		// No prompt visible — terminal is idle but not at Claude's input.
		reportStatus(.active)
	}

	/// Whether the viewport is showing the bottom of the buffer, where the live screen sits.
	/// `canScroll` is false while there is no scrollback to move through, and for the alternate
	/// buffer, both of which only ever display the live screen.
	private var isShowingLiveScreen: Bool {
		!canScroll || scrollPosition >= 1
	}

	private func reportStatus(_ status: TerminalSessionStatus) {
		guard status != currentStatus else {
			return
		}

		currentStatus = status
		onStatusChange?(sessionId, status)
	}
}

// MARK: - Shell Escaping

private extension String {
	/// Backslash-escapes shell-special characters so the path can be used as-is
	/// at the command line without surrounding quotes.
	/// e.g. `/foo bar` → `/foo\ bar`, `/it's` → `/it\'s`
	var shellEscaped: String {
		let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/-_.,=@:+"))
		return unicodeScalars.reduce(into: "") { result, scalar in
			if safe.contains(scalar) {
				result.append(Character(scalar))
			}
			else {
				result += "\\\(Character(scalar))"
			}
		}
	}
}

// MARK: - TerminalProcessDelegate

public final class TerminalProcessDelegate: LocalProcessTerminalViewDelegate {
	private let onFailed: @Sendable (String) -> Void

	public init(onFailed: @escaping @Sendable (String) -> Void) {
		self.onFailed = onFailed
	}

	public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

	public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

	public func processTerminated(source: TerminalView, exitCode: Int32?) {
		let message = "Terminal process exited (code \(exitCode ?? -1))"
		let callback = onFailed
		DispatchQueue.main.async {
			callback(message)
		}
	}

	public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
}
