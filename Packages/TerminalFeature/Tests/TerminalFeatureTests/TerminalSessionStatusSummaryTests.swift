import Foundation
import Testing

@testable import TerminalFeature

struct TerminalSessionStatusSummaryTests {
	private func session(_ repositoryPath: String, _ status: TerminalSessionStatus) -> TerminalSession {
		var session = TerminalSession(repositoryPath: repositoryPath)
		session.status = status
		return session
	}

	@Test("a repository shows the most pressing status among its tabs, whatever their order")
	func mostPressingStatusWins() {
		let statuses: [TerminalSessionStatus] = [.failed("boom"), .launching, .active, .waitingForInput]
		for (lower, lowerStatus) in statuses.enumerated() {
			for higherStatus in statuses[lower...] {
				#expect(lowerStatus.summarized(with: higherStatus) == higherStatus)
				#expect(higherStatus.summarized(with: lowerStatus) == higherStatus)
			}
		}
	}

	@Test("each repository gets its own summary")
	func oneStatusPerRepository() {
		let sessions = [
			session("/repos/alpha", .active),
			session("/repos/alpha", .waitingForInput),
			session("/repos/alpha", .launching),
			session("/repos/beta", .failed("boom")),
			session("/repos/beta", .active),
			session("/repos/gamma", .failed("boom")),
		]

		#expect(sessions.statusByRepository == [
			"/repos/alpha": .waitingForInput,
			"/repos/beta": .active,
			"/repos/gamma": .failed("boom"),
		])
	}
}
