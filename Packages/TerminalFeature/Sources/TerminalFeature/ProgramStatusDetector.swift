import Foundation
import OSLog

/// Decides whether a pane is waiting for the user or working, from what the program in it says
/// about itself.
///
/// Programs that speak OSC 7501, the Program Status Protocol — Claude Code since 2.1.295, among
/// others — report their state, and SwiftTerm parses the reports into records: `working` while
/// they run, `blocked` while a dialog (a permission prompt, a question, a login) is up, and
/// `done`, `idle` or `error` once there is nothing left to do. Anything but `working` is the
/// program waiting for the user. A pane without a report — a plain shell, a build, an older
/// Claude — is active.
///
/// A report outlives a program that crashed without clearing it, so once the pane falls quiet, a
/// report is set aside while the shell has the foreground back. Nothing else moves the status:
/// not the user's input (typing into Claude's input box leaves it `done` until the prompt is
/// sent, and then it reports `working` itself), and not a notification the program asks for.
@MainActor
final class ProgramStatusDetector {
	private static let isTracing = ProcessInfo.processInfo.environment["BC_TERMINAL_STATUS_LOG"] != nil

	private static let log = Logger(subsystem: "com.bridgecommander.terminal", category: "status")

	/// Names the pane in a trace.
	private let label: String

	/// Whether the pane's shell holds its foreground — at its prompt, with no program running —
	/// or `nil` when that can't be told.
	private let isShellInForeground: () -> Bool?

	/// How long the pane must be quiet before the foreground is checked.
	private let foregroundCheckDelay: TimeInterval

	/// The report travels with a change to `.waitingForInput`, so the notification can say who is
	/// waiting and why.
	private let onStatusChange: (TerminalSessionStatus, TerminalProgramReport?) -> Void

	private var currentStatus: TerminalSessionStatus = .active
	private var pendingForegroundCheck: DispatchWorkItem?

	/// Set once the pane's session is killed. The shell's exit writes a last frame, and acting on it
	/// would report a status for a session that no longer exists.
	private(set) var isStopped = false

	/// The pane's root record, or `nil` while no program reports anything.
	private var report: TerminalProgramReport?

	/// Set when the last foreground check found the shell back in the foreground while a report
	/// stood: a program that crashed or was suspended, leaving its last report behind. Cleared by
	/// the next report, or by a check that finds a program in the foreground again.
	private var isReportLeftBehind = false

	init(
		label: String,
		isShellInForeground: @escaping () -> Bool?,
		foregroundCheckDelay: TimeInterval = 1.5,
		onStatusChange: @escaping (TerminalSessionStatus, TerminalProgramReport?) -> Void
	) {
		self.label = label
		self.isShellInForeground = isShellInForeground
		self.foregroundCheckDelay = foregroundCheckDelay
		self.onStatusChange = onStatusChange
	}

	// MARK: - Events

	/// Takes in the pane's root OSC 7501 record, `nil` once there is none (Claude clears its records
	/// when it exits).
	func statusReported(_ report: TerminalProgramReport?) {
		guard !isStopped else {
			return
		}

		trace("\(report?.program ?? "no program") reports \(report.map { "\($0.state)" } ?? "nothing")")
		self.report = report
		isReportLeftBehind = false
		reportStatus(derivedStatus, reason: "the program's report")
	}

	/// Takes in a burst of output written by the child process. Re-arms the foreground check while a
	/// report stands: the shell drawing its prompt after a crashed program is output too.
	func outputReceived() {
		guard !isStopped, report != nil else {
			return
		}

		pendingForegroundCheck?.cancel()
		let check = DispatchWorkItem { [weak self] in
			self?.checkForeground()
		}
		pendingForegroundCheck = check
		DispatchQueue.main.asyncAfter(deadline: .now() + foregroundCheckDelay, execute: check)
	}

	/// Ends all reporting. Called when the pane's session is killed, before the shell is hung up:
	/// the exit writes a last frame, and there is nobody left to hear what it looks like.
	func stop() {
		isStopped = true
		pendingForegroundCheck?.cancel()
		pendingForegroundCheck = nil
	}

	/// Sets aside a report once the shell has the foreground back, and takes it up again once a
	/// program has it (a Claude suspended with Ctrl-Z and brought back with `fg` does not report
	/// again until its state changes). A foreground that can't be told leaves the report standing.
	/// Called on the debounce, and directly by tests so they need not wait one out.
	func checkForeground() {
		guard !isStopped, report != nil else {
			return
		}

		let isLeftBehind = isShellInForeground() == true
		guard isLeftBehind != isReportLeftBehind else {
			return
		}

		isReportLeftBehind = isLeftBehind
		reportStatus(
			derivedStatus,
			reason: isLeftBehind ? "the shell back in the foreground" : "a program back in the foreground"
		)
	}

	// MARK: - Reporting

	/// Whether the program in the pane stands behind a report: one was made and has not been set
	/// aside as left behind. A notification such a program asks for repeats what its report says.
	var isReportStanding: Bool {
		report != nil && !isReportLeftBehind
	}

	private var derivedStatus: TerminalSessionStatus {
		guard let report, !isReportLeftBehind else {
			return .active
		}

		return Self.status(for: report.state)
	}

	/// What a reported state means for the pane: only work in progress is not waiting.
	static func status(for state: TerminalProgramReport.State) -> TerminalSessionStatus {
		switch state {
		case .working:
			.active
		case .blocked,
		     .done,
		     .error,
		     .idle:
			.waitingForInput
		}
	}

	private func reportStatus(_ status: TerminalSessionStatus, reason: @autoclosure () -> String) {
		guard status != currentStatus else {
			return
		}

		trace("\(currentStatus) → \(status) on \(reason())")
		currentStatus = status
		onStatusChange(status, status == .waitingForInput ? report : nil)
	}

	/// Records a status decision when `BC_TERMINAL_STATUS_LOG` is set in the environment. Read it
	/// with `log stream --predicate 'subsystem == "com.bridgecommander.terminal"'`, or from Xcode's
	/// console.
	private func trace(_ message: @autoclosure () -> String) {
		guard Self.isTracing else {
			return
		}

		let text = message()
		Self.log.notice("\(self.label, privacy: .public): \(text, privacy: .public)")
	}
}
