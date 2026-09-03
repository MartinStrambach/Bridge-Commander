import Foundation
import OSLog

/// Decides whether a pane is waiting for the user at Claude's prompt, or working.
///
/// The signal is silence from the child process, qualified by the prompt being on screen. Output on
/// its own settles nothing: much of it is provoked by the app rather than by Claude, since resizing
/// a pane makes its child repaint, and reading that as work turned the whole sidebar green whenever
/// the user switched repository. Two things move the status. Keystrokes release a waiting pane at
/// once, the user asking Claude for something being the very reason it goes back to work. Otherwise
/// an idle check, run once the pane has fallen quiet, reads the screen and reports what it finds.
@MainActor
final class ClaudeStatusDetector {
	private static let promptScalar: UInt32 = 0x276F // ❯

	/// Claude draws its input prompt at column 0 and the arrow of a selected option at column 1.
	/// The bound leaves room for small layout changes while rejecting the glyph where it can only be
	/// ordinary output: mid-line in a diff, a log message, or a file being printed.
	private static let promptColumns = 5

	/// Both prompt shapes sit on the last rendered lines, so the walk gives up after this many rows
	/// with content on them. A `❯` further up the screen is scrollback, not a live prompt.
	private static let maxInspectedRows = 12

	private static let isTracing = ProcessInfo.processInfo.environment["BC_TERMINAL_STATUS_LOG"] != nil

	private static let log = Logger(subsystem: "com.bridgecommander.terminal", category: "status")

	/// The pane being judged. Weak because the pane owns its detector.
	private weak var screen: (any PromptScreen)?

	/// Names the pane in a trace.
	private let label: String

	/// How long the pane must be quiet before its screen is judged.
	private let idleThreshold: TimeInterval

	private let onStatusChange: (TerminalSessionStatus) -> Void

	private var currentStatus: TerminalSessionStatus = .active
	private var pendingCheck: DispatchWorkItem?

	/// Set once the pane's session is killed. The shell's exit writes a last frame, and judging it
	/// would report a status for a session that no longer exists.
	private var isStopped = false

	private var renderTracker = RenderTracker()

	/// Holds a waiting pane until a second idle check agrees it has gone back to work.
	private let waitingStateGate = WaitingStateGate()

	init(
		label: String,
		screen: any PromptScreen,
		idleThreshold: TimeInterval = 1.5,
		onStatusChange: @escaping (TerminalSessionStatus) -> Void
	) {
		self.label = label
		self.screen = screen
		self.idleThreshold = idleThreshold
		self.onStatusChange = onStatusChange
	}

	// MARK: - Events

	/// Takes in a burst of output written by the child process.
	func outputReceived(_ slice: ArraySlice<UInt8>) {
		guard !isStopped else {
			return
		}

		renderTracker.received(slice)
		scheduleIdleCheck()
	}

	/// Takes in bytes sent to the child process, whether typed, pasted or dropped.
	func inputSent(_ data: ArraySlice<UInt8>) {
		guard !isStopped else {
			return
		}

		// A focus report is the terminal answering the repository switch, not the user typing.
		if FocusReport.matches(data) {
			scheduleIdleCheck()
			return
		}

		if currentStatus == .waitingForInput {
			reportStatus(.active, reason: "user input")
		}
		waitingStateGate.reset()
		// Input has to re-arm the check too. A key that Claude doesn't echo produces no output, and
		// without this the pane would sit on a stale `.active` until it wrote something again.
		scheduleIdleCheck()
	}

	/// Ends all reporting. Called when the pane's session is killed, before the shell is hung up:
	/// the exit writes a last frame, and there is nobody left to hear what it looks like.
	func stop() {
		isStopped = true
		pendingCheck?.cancel()
		pendingCheck = nil
	}

	// MARK: - Idle checking

	private func scheduleIdleCheck() {
		pendingCheck?.cancel()
		let check = DispatchWorkItem { [weak self] in
			self?.checkIdleState()
		}
		pendingCheck = check
		DispatchQueue.main.asyncAfter(deadline: .now() + idleThreshold, execute: check)
	}

	/// Judges the pane's screen and reports the result, subject to the gate on leaving the waiting
	/// state. Called on the debounce, and directly by tests so they need not wait one out.
	func checkIdleState() {
		guard !isStopped else {
			return
		}

		renderTracker.markJudged()

		guard let screen else {
			return
		}

		let verdict = idleVerdict(on: screen)
		switch waitingStateGate.decide(verdict: verdict.status, currentStatus: currentStatus) {
		case let .report(status):
			reportStatus(status, reason: "idle check, \(verdict)")

		case .waitForConfirmation:
			// Look again once the pane has been quiet for another interval. A screen caught
			// mid-repaint has settled by then, and a pane that really is working will still have no
			// prompt on it.
			trace("held waiting on a first \(verdict)")
			scheduleIdleCheck()
		}
	}

	/// What an idle check concluded, and from what evidence. The reason travels with the status so a
	/// trace can say why a dot moved: this heuristic reads a moving screen, and the moment it gets
	/// something wrong is over before anyone can look.
	private enum IdleVerdict {
		/// Something other than Claude owns the pane, so the prompt glyph carries no meaning.
		case foregroundIsNotClaude
		/// The user is reading scrollback, so the last frame drawn is judged in place of the grid.
		case scrolledBack(drewPrompt: Bool)
		/// The cursor is sitting in the input box Claude drew.
		case cursorAtPrompt
		/// The prompt glyph is on screen, on this row.
		case promptOnScreen(row: Int)
		/// The pane is quiet, with no prompt in the rows Claude would have drawn one in.
		case noPromptOnScreen

		var status: TerminalSessionStatus {
			switch self {
			case .foregroundIsNotClaude,
			     .noPromptOnScreen:
				.active

			case let .scrolledBack(drewPrompt):
				drewPrompt ? .waitingForInput : .active

			case .cursorAtPrompt,
			     .promptOnScreen:
				.waitingForInput
			}
		}
	}

	/// Whether Claude is sitting at a prompt: its input box, or the arrow marking the selected
	/// option of a dialog.
	///
	/// The glyph alone is weak evidence, so it is qualified twice over. The pane must have Claude in
	/// the foreground, since a shell prompt theme, a diff or scrollback can all put `❯` on screen.
	/// And the hit must land where Claude puts a prompt rather than anywhere at all.
	///
	/// Runs for every open pane after every burst of output, so the reads are kept cheap. A pane
	/// that isn't running Claude skips the screen entirely. The cursor's row is tried first, and
	/// otherwise rows are walked from the bottom, where the prompt lives, so a hit usually lands
	/// within a row or two instead of after a full traversal.
	private func idleVerdict(on screen: any PromptScreen) -> IdleVerdict {
		// An unidentifiable foreground process falls through to the screen rather than being taken
		// for something other than Claude.
		if screen.isClaudeInForeground == false {
			return .foregroundIsNotClaude
		}

		guard screen.isShowingLiveScreen else {
			return .scrolledBack(drewPrompt: renderTracker.drewPrompt)
		}

		// The cursor is the surest anchor for the input box: while Claude waits, it sits in the box
		// just after the `❯` that was drawn. Worth reading before the walk, because a resize can
		// leave the tail of the previous frame below the new one, and the walk would then spend its
		// whole row budget on that stale content and conclude there is no prompt.
		if drawsPrompt(row: screen.cursorRow, on: screen) == true {
			return .cursorAtPrompt
		}

		var inspectedRows = 0
		for row in stride(from: screen.rowCount - 1, through: 0, by: -1) {
			guard let drawsPrompt = drawsPrompt(row: row, on: screen) else {
				continue // nothing written on this row
			}

			if drawsPrompt {
				return .promptOnScreen(row: row)
			}

			inspectedRows += 1
			if inspectedRows == Self.maxInspectedRows {
				break
			}
		}

		return .noPromptOnScreen
	}

	/// Whether `row` draws Claude's prompt glyph where Claude would put it, or `nil` when the row is
	/// blank.
	private func drawsPrompt(row: Int, on screen: any PromptScreen) -> Bool? {
		screen.row(row, drawsScalar: Self.promptScalar, withinColumns: Self.promptColumns)
	}

	// MARK: - Reporting

	private func reportStatus(_ status: TerminalSessionStatus, reason: @autoclosure () -> String) {
		guard status != currentStatus else {
			return
		}

		trace("\(currentStatus) → \(status) on \(reason())")
		currentStatus = status
		onStatusChange(status)
	}

	/// Records a status decision when `BC_TERMINAL_STATUS_LOG` is set in the environment. Read it
	/// with `log stream --predicate 'subsystem == "com.bridgecommander.terminal"'`, or from Xcode's
	/// console. Off by default: every pane decides this after every burst of output.
	private func trace(_ message: @autoclosure () -> String) {
		guard Self.isTracing else {
			return
		}

		let text = message()
		Self.log.notice("\(self.label, privacy: .public): \(text, privacy: .public)")
	}
}
