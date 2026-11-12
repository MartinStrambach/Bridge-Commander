import Foundation

/// Spaces out each terminal tab's notifications, as the Program Status Protocol asks of anything a
/// program's report causes outside the terminal: a program flipping between working and waiting
/// would otherwise alert, with a sound, on every flip.
///
/// A trailing throttle per tab. The first notification shows at once; one asked for sooner than
/// `interval` after the last shown waits out the rest, and a newer one asked for meanwhile takes
/// its place, so the tab's latest news is never lost — only the alerts in between.
struct NotificationThrottle {
	let interval: TimeInterval

	private var lastShown: [UUID: Date] = [:]
	/// The ticket of each tab's newest notification not yet shown.
	private var pendingTicket: [UUID: Int] = [:]
	private var lastTicket = 0

	init(interval: TimeInterval) {
		self.interval = interval
	}

	/// Takes in a notification for tab `id`, asked for at `now`: its ticket, and how long to wait
	/// before showing it.
	mutating func schedule(_ id: UUID, at now: Date) -> (ticket: Int, delay: TimeInterval) {
		lastTicket += 1
		pendingTicket[id] = lastTicket
		let earliest = lastShown[id].map { $0.addingTimeInterval(interval) } ?? now
		return (lastTicket, max(0, earliest.timeIntervalSince(now)))
	}

	/// Whether the notification holding `ticket` is still the tab's newest, after its wait; if so,
	/// it counts as shown at `now`.
	mutating func claim(_ id: UUID, ticket: Int, at now: Date) -> Bool {
		guard pendingTicket[id] == ticket else {
			return false
		}

		pendingTicket[id] = nil
		lastShown[id] = now
		return true
	}

	/// Drops the tab's notification still waiting, as when the tab's notification is withdrawn. The
	/// time of the last one shown stays, so withdrawing does not reset the spacing.
	mutating func cancel(_ id: UUID) {
		pendingTicket[id] = nil
	}
}
