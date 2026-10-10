/// Which of the two ways a program in a built-in terminal tab can ask for the user posts the
/// notification: its status reports (OSC 7501 — waiting, done, failed, with what for), or the
/// notifications it sends itself (OSC 9 / OSC 777). A program may send both for the same moment —
/// Claude Code does once its notification channel is Ghostty — and posting both would alert twice.
public nonisolated enum TerminalNotificationSource: String, CaseIterable, Equatable, Sendable {
	/// Status reports from a program that sends them; the program's own notifications from one that
	/// does not, or once it has stopped reporting.
	case automatic
	case statusReports
	case programNotifications

	public static let `default` = Self.automatic

	public var displayName: String {
		switch self {
		case .automatic:
			"Automatic"
		case .statusReports:
			"Status reports only (OSC 7501)"
		case .programNotifications:
			"Program notifications only (OSC 9 / OSC 777)"
		}
	}

	public var explanation: String {
		switch self {
		case .automatic:
			"A program that reports its status (Claude Code 2.1.295 and later) notifies when it is waiting, done or failed; its own notifications are left out so nothing is posted twice. Other programs notify as they ask to."
		case .statusReports:
			"Only programs that report their status notify, when they are waiting, done or failed. Notifications programs send themselves are never shown."
		case .programNotifications:
			"Only notifications programs send themselves are shown, as in Ghostty. For Claude Code, set its notification channel to Ghostty in /config. Status reports still color the tab's dot."
		}
	}

	/// Whether a change to waiting that a program reported posts a notification.
	public var postsStatusReports: Bool {
		self != .programNotifications
	}

	/// Whether a notification a program sent itself is posted, given whether that program reports
	/// its status.
	public func postsProgramNotification(fromStatusReportingProgram: Bool) -> Bool {
		switch self {
		case .automatic:
			!fromStatusReportingProgram
		case .statusReports:
			false
		case .programNotifications:
			true
		}
	}
}
