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
///
/// Silence alone cannot tell a finished turn from a working one that paused, because Claude keeps
/// its input box, prompt glyph and all, on screen while it works. Claude's own progress reports
/// (OSC 9;4, enabled by `TerminalEnvironment`) settle that: between "working" and "done" an idle
/// check ignores the input box and only a dialog — a numbered option list such as a permission
/// prompt, which Claude shows mid-turn — counts as waiting.
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

	/// Set when the program in the pane asked for a notification, and cleared by the user's next
	/// keystroke. While set, idle checks do not release the pane: the program said it wants the
	/// user, and nothing on screen can say otherwise — a notification from a build or a test run
	/// comes with no Claude prompt to find, and would read as `.active` at the next quiet interval.
	private var isHeldForAttention = false

	/// Set while Claude reports a turn in progress (OSC 9;4 with a working state), cleared when it
	/// reports the turn done. Never set by a Claude that does not report progress, which leaves
	/// the screen-only judgement in charge.
	private var isClaudeWorking = false

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

		// A reply is the terminal answering a focus change or a query, not the user typing.
		if TerminalReply.matches(data) {
			scheduleIdleCheck()
			return
		}

		isHeldForAttention = false
		if currentStatus == .waitingForInput {
			reportStatus(.active, reason: "user input")
		}
		waitingStateGate.reset()
		// Input has to re-arm the check too. A key that Claude doesn't echo produces no output, and
		// without this the pane would sit on a stale `.active` until it wrote something again.
		scheduleIdleCheck()
	}

	/// Takes in a notification the program in the pane asked for (OSC 9 or OSC 777). The pane is
	/// waiting from now until the user types. Its session learns that together with the
	/// notification rather than through `onStatusChange`, so the two do not each post one.
	///
	/// - Returns: `false` once the detector is stopped, when the notification belongs to a
	///   session that is going away and should not be shown.
	func attentionRequested() -> Bool {
		guard !isStopped else {
			return false
		}

		trace("\(currentStatus) → waitingForInput on a notification request")
		isHeldForAttention = true
		currentStatus = .waitingForInput
		waitingStateGate.reset()
		return true
	}

	/// Takes in a progress report (OSC 9;4) from the program in the pane. Claude Code sends one when
	/// a turn starts and another when it ends.
	///
	/// A turn starting releases a waiting pane at once. A turn ending reports nothing by itself:
	/// Claude also clears its progress on exit, so "done" may mean the shell is about to come back.
	/// The next idle check sees which, the same way it does without progress reports.
	func progressReported(isWorking: Bool) {
		guard !isStopped else {
			return
		}

		// A progress bar from some other program says nothing about Claude.
		if screen?.isClaudeInForeground == false {
			return
		}

		trace("progress report, working: \(isWorking)")
		isClaudeWorking = isWorking
		if isWorking {
			isHeldForAttention = false
			waitingStateGate.reset()
			if currentStatus == .waitingForInput {
				reportStatus(.active, reason: "progress report")
			}
		}
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
		if isHeldForAttention, verdict.status == .active {
			trace("held waiting for attention over \(verdict)")
			return
		}

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
		/// Claude reported a turn in progress and shows no dialog. Its input box may be on screen.
		case claudeReportsWork
		/// Claude reported a turn in progress, and a numbered option list is on screen, on this row.
		case dialogOnScreen(row: Int)
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
			case .claudeReportsWork,
			     .foregroundIsNotClaude,
			     .noPromptOnScreen:
				.active

			case .dialogOnScreen:
				.waitingForInput

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
			// A Claude that exits without clearing its progress must not leave the next one, or
			// the shell, judged as mid-turn.
			isClaudeWorking = false
			return .foregroundIsNotClaude
		}

		if isClaudeWorking {
			return workingVerdict(on: screen)
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

	/// The verdict while Claude reports a turn in progress: waiting only when a dialog is up.
	///
	/// A dialog is told from the input box by what follows the glyph: an option number (`❯ 1. Yes`).
	/// Scrollback is not judged, since the last frame drawn says only that a glyph was drawn, not
	/// which kind.
	private func workingVerdict(on screen: any PromptScreen) -> IdleVerdict {
		guard screen.isShowingLiveScreen else {
			return .claudeReportsWork
		}

		if drawsDialogOption(row: screen.cursorRow, on: screen) == true {
			return .dialogOnScreen(row: screen.cursorRow)
		}

		var inspectedRows = 0
		for row in stride(from: screen.rowCount - 1, through: 0, by: -1) {
			guard let drawsOption = drawsDialogOption(row: row, on: screen) else {
				continue // nothing written on this row
			}

			if drawsOption {
				return .dialogOnScreen(row: row)
			}

			inspectedRows += 1
			if inspectedRows == Self.maxInspectedRows {
				break
			}
		}

		return .claudeReportsWork
	}

	/// Whether `row` draws a dialog's selected option, or `nil` when the row is blank. The cheap
	/// glyph scan runs first, so text is read only from a row that has the glyph.
	private func drawsDialogOption(row: Int, on screen: any PromptScreen) -> Bool? {
		guard let drawsPrompt = drawsPrompt(row: row, on: screen) else {
			return nil
		}

		guard drawsPrompt else {
			return false
		}

		let text = screen.leadingText(ofRow: row, columns: Self.promptColumns + Self.optionNumberColumns)
		return Self.isNumberedOption(text)
	}

	/// Room after the glyph's column for a space, an option number and its period.
	private static let optionNumberColumns = 6

	/// Whether `text` holds the prompt glyph followed by an option number: `❯ 1.`, `❯ 12.`.
	static func isNumberedOption(_ text: String) -> Bool {
		guard let glyph = text.unicodeScalars.firstIndex(where: { $0.value == promptScalar }) else {
			return false
		}

		let rest = text.unicodeScalars[text.unicodeScalars.index(after: glyph)...]
			.drop { $0 == " " || $0 == "\u{A0}" }
		let digits = rest.prefix { ("0" ... "9").contains($0) }
		return !digits.isEmpty && rest.dropFirst(digits.count).first == "."
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
