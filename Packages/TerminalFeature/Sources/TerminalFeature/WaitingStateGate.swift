import Synchronization

/// Decides what the verdict of an idle check does to a pane's reported status.
///
/// Only one direction is gated. A verdict that would release a pane from `waitingForInput` has to
/// be seen twice, because a single verdict can be read off a screen that is mid-repaint: the app
/// resizes every open pane when the user switches repository, and the frame each child redraws in
/// response is briefly a screen with no prompt on it. Acting on that one verdict is what made the
/// sidebar dot flash green and settle back. Everything else is reported as it comes, so a pane that
/// starts waiting still shows it at the first opportunity.
///
/// The streak is held under a lock, so the gate carries its own guarantee rather than borrowing one
/// from whoever calls it. Its caller is main actor isolated, which already serialises the calls, but
/// the count is the one piece of state a lost or doubled update would corrupt silently: the pane
/// would either never be released or be released on a single verdict, which is the bug this type
/// exists to prevent.
final nonisolated class WaitingStateGate: Sendable {
	enum Decision: Equatable, Sendable {
		/// Report this status to the session.
		case report(TerminalSessionStatus)
		/// Leave the status alone and look again after another quiet interval.
		case waitForConfirmation
	}

	/// How many agreeing verdicts release a waiting pane.
	private static let verdictsToRelease = 2

	private let agreeingVerdicts = Mutex<Int>(0)

	func decide(
		verdict: TerminalSessionStatus,
		currentStatus: TerminalSessionStatus
	) -> Decision {
		agreeingVerdicts.withLock { count in
			guard verdict == .active, currentStatus == .waitingForInput else {
				count = 0
				return .report(verdict)
			}

			count += 1
			guard count >= Self.verdictsToRelease else {
				return .waitForConfirmation
			}

			count = 0
			return .report(.active)
		}
	}

	/// Drops a part-built streak. Used when something outside the idle checks settles what the pane
	/// is doing, such as the user typing into it.
	func reset() {
		agreeingVerdicts.withLock { $0 = 0 }
	}
}
