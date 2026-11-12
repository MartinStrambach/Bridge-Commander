import Foundation
import Testing
@testable import ToolsIntegration

@Suite("Notification throttle")
struct NotificationThrottleTests {
	private let tab = UUID()
	private let start = Date(timeIntervalSinceReferenceDate: 0)

	@Test("a tab's first notification shows at once")
	func firstShowsAtOnce() {
		var throttle = NotificationThrottle(interval: 2)

		let (ticket, delay) = throttle.schedule(tab, at: start)

		#expect(delay == 0)
		let isShown = throttle.claim(tab, ticket: ticket, at: start)
		#expect(isShown)
	}

	@Test("one asked for too soon waits out the rest of the interval")
	func tooSoonWaits() {
		var throttle = NotificationThrottle(interval: 2)
		let first = throttle.schedule(tab, at: start)
		_ = throttle.claim(tab, ticket: first.ticket, at: start)

		let second = throttle.schedule(tab, at: start.addingTimeInterval(0.5))

		#expect(second.delay == 1.5)
		let isShown = throttle.claim(tab, ticket: second.ticket, at: start.addingTimeInterval(2))
		#expect(isShown)
	}

	@Test("of several waiting, only the latest is shown")
	func latestWins() {
		var throttle = NotificationThrottle(interval: 2)
		let first = throttle.schedule(tab, at: start)
		_ = throttle.claim(tab, ticket: first.ticket, at: start)

		let waiting = throttle.schedule(tab, at: start.addingTimeInterval(0.5))
		let newer = throttle.schedule(tab, at: start.addingTimeInterval(1))

		#expect(waiting.delay == 1.5)
		#expect(newer.delay == 1, "it shows when the older one would have")
		let isOlderShown = throttle.claim(tab, ticket: waiting.ticket, at: start.addingTimeInterval(2))
		let isNewerShown = throttle.claim(tab, ticket: newer.ticket, at: start.addingTimeInterval(2))
		#expect(!isOlderShown)
		#expect(isNewerShown)
	}

	@Test("a withdrawn notification still waiting is dropped, and the spacing stays")
	func cancelDropsWaiting() {
		var throttle = NotificationThrottle(interval: 2)
		let first = throttle.schedule(tab, at: start)
		_ = throttle.claim(tab, ticket: first.ticket, at: start)
		let waiting = throttle.schedule(tab, at: start.addingTimeInterval(0.5))

		throttle.cancel(tab)

		let isShown = throttle.claim(tab, ticket: waiting.ticket, at: start.addingTimeInterval(2))
		let next = throttle.schedule(tab, at: start.addingTimeInterval(1))
		#expect(!isShown)
		#expect(next.delay == 1)
	}

	@Test("tabs are spaced independently")
	func perTab() {
		var throttle = NotificationThrottle(interval: 2)
		let first = throttle.schedule(tab, at: start)
		_ = throttle.claim(tab, ticket: first.ticket, at: start)

		let otherTab = throttle.schedule(UUID(), at: start)
		#expect(otherTab.delay == 0)
	}

	@Test("once the interval has passed, the next shows at once")
	func afterInterval() {
		var throttle = NotificationThrottle(interval: 2)
		let first = throttle.schedule(tab, at: start)
		_ = throttle.claim(tab, ticket: first.ticket, at: start)

		let next = throttle.schedule(tab, at: start.addingTimeInterval(5))
		#expect(next.delay == 0)
	}
}
