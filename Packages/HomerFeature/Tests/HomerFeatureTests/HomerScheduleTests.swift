import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer schedules")
struct HomerScheduleTests {
	private func agent(_ name: String, cron nextRunAt: Double??) -> HomerAgent {
		HomerAgent(
			name: name,
			cron: nextRunAt.map { HomerAgent.Cron(expression: "* * * * *", timezone: "UTC", nextRunAt: $0) }
		)
	}

	@Test("only agents with a cron, soonest next run first, unknown next runs last")
	func sortsByNextRun() {
		let agents = [
			agent("a-unscheduled", cron: .none),
			agent("b-later", cron: 2000),
			agent("c-no-next-run", cron: .some(nil)),
			agent("d-soon", cron: 1000),
			agent("e-later-too", cron: 2000),
			agent("f-no-next-run", cron: .some(nil)),
		]

		#expect(HomerAgent.schedules(agents).map(\.name) == [
			"d-soon",
			// Ties keep the list's order.
			"b-later",
			"e-later-too",
			"c-no-next-run",
			"f-no-next-run",
		])
	}

	@Test("the countdown reads as the console's formatTimeUntil")
	func countdown() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		#expect(HomerFormat.timeUntil(1_000_000 + 2 * 3600 + 3 * 60 + 5, now: now) == "in 2h 3m")
		#expect(HomerFormat.timeUntil(1_000_000 + 26 * 3600, now: now) == "in 1d 2h")
		#expect(HomerFormat.timeUntil(1_000_000 + 45, now: now) == "in 45s")
		#expect(HomerFormat.timeUntil(1_000_000, now: now) == "expired")
	}
}
