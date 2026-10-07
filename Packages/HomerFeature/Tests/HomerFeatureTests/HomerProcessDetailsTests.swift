import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer console formats")
struct HomerFormatTests {
	@Test("timestamps read like the console's")
	func timestamp() throws {
		let utc = try #require(TimeZone(identifier: "UTC"))

		#expect(HomerFormat.timestamp(1_700_000_100, timeZone: utc) == "14.11.23 22:15:00")
	}

	@Test("cost keeps four decimals")
	func cost() {
		#expect(HomerFormat.cost(0.42113) == "$0.4211")
		#expect(HomerFormat.cost(12) == "$12.0000")
	}

	private static let countdowns: [(offset: Double, expected: String)] = [
		(30, "in 30s"),
		(725, "in 12m"),
		(15000, "in 4h 10m"),
		(183_600, "in 2d 3h"),
		(0, "expired"),
		(-60, "expired"),
	]

	@Test("purge countdown", arguments: countdowns)
	func timeUntil(offset: Double, expected: String) {
		let now = Date(timeIntervalSince1970: 1_700_000_000)

		#expect(HomerFormat.timeUntil(1_700_000_000 + offset, now: now) == expected)
	}
}

@Suite("Homer kill and retry permissions")
struct HomerCapabilityTests {
	private let factoryRun = HomerProcess(id: 1, status: .working, agentName: "factory-developer", owner: "cron")

	@Test("an admin may do anything")
	func admin() {
		let user = HomerUser(username: "admin", role: "admin")

		#expect(user.canKill(factoryRun))
		#expect(user.canRetry(factoryRun))
	}

	@Test("a user may kill their own console run without any grant")
	func owner() {
		let user = HomerUser(username: "martin")
		var run = factoryRun
		run.owner = "session:martin"

		#expect(user.canKill(run))
		#expect(!user.canRetry(run))
	}

	@Test("grants match exact names and prefix patterns")
	func grants() {
		let user = HomerUser(username: "ops", grants: [
			.init(agents: ["factory*"], actions: ["read", "control"]),
			.init(agents: ["product-buddy"], actions: ["run"]),
		])

		#expect(user.canKill(factoryRun))
		#expect(!user.canRetry(factoryRun))
		#expect(!user.canKill(HomerProcess(id: 2, status: .working, agentName: "deploy")))
	}

	@Test("retry needs the run to be visible as well as runnable")
	func retryNeedsRead() {
		let runOnly = HomerUser(username: "bot", grants: [.init(agents: ["*"], actions: ["run"])])
		let readAndRun = HomerUser(username: "bot", grants: [.init(agents: ["*"], actions: ["run", "read"])])

		#expect(!runOnly.canRetry(factoryRun))
		#expect(readAndRun.canRetry(factoryRun))
	}
}

@Suite("Homer flow summary")
struct HomerFlowSummaryTests {
	private func page(_ processes: [HomerProcess], total: Int? = nil) -> HomerProcessPage {
		HomerProcessPage(processes: processes, total: total ?? processes.count)
	}

	@Test("a question outranks a running run")
	func questionFirst() {
		let summary = HomerFlowSummary(page: page([
			HomerProcess(id: 2, status: .working, agentName: "a", openQuestions: 1, costUsd: 0.5),
			HomerProcess(id: 3, status: .created, agentName: "b", costUsd: 0.25),
		]))

		#expect(summary == HomerFlowSummary(runCount: 2, costUsd: 0.75, state: .question, isPartial: false))
	}

	@Test("a killed run reads as failed, and an all-finished flow as finished")
	func failedAndFinished() {
		#expect(HomerFlowSummary(page: page([
			HomerProcess(id: 2, status: .finished, agentName: "a"),
			HomerProcess(id: 3, status: .killed, agentName: "b"),
		])).state == .failed)
		#expect(HomerFlowSummary(page: page([HomerProcess(id: 2, status: .finished, agentName: "a")])).state == .finished)
	}

	@Test("an empty flow has no state, a cut-short one is partial")
	func emptyAndPartial() {
		#expect(HomerFlowSummary(page: page([])).state == nil)
		#expect(HomerFlowSummary(page: page([HomerProcess(id: 2, status: .finished, agentName: "a")], total: 140)).isPartial)
	}
}

@Suite("Homer process details decoding")
struct HomerProcessDetailsDecodingTests {
	@Test("runner, purge time, flow ids and the user's grants decode")
	func decodes() throws {
		let processJSON = """
			{ "id": 9, "status": "FINISHED", "agentName": "factory", "owner": "session:admin",
			  "history": [], "executions": [], "currentCommand": null, "currentCommandStart": null,
			  "purgeAt": 1700007200, "parentProcessId": 4, "rootProcessId": 1,
			  "runner": { "alias": null, "type": "kubernetes", "podName": "homer-9", "podPhase": "SUCCEEDED" } }
			"""
		let meJSON = """
			{ "username": "ops", "role": null, "grants": [ { "agents": ["factory*"], "actions": ["read"] } ] }
			"""

		let process = try JSONDecoder().decode(HomerProcess.self, from: Data(processJSON.utf8))
		let user = try JSONDecoder().decode(HomerUser.self, from: Data(meJSON.utf8))

		#expect(process.purgeAt == 1_700_007_200)
		#expect(process.parentProcessId == 4)
		#expect(process.rootProcessId == 1)
		#expect(process.runner == .init(type: "kubernetes", podName: "homer-9", podPhase: "SUCCEEDED"))
		#expect(process.runner?.displayName == "kubernetes")
		#expect(user.grants == [.init(agents: ["factory*"], actions: ["read"])])
		#expect(!user.isAdmin)
	}

	@Test("every filter goes on the query")
	func fullQuery() {
		let query = HomerProcessQuery(
			statuses: [.working],
			agentName: "factory",
			tags: ["ticket:MOB-1", "repo:ios"],
			parentProcessId: 4,
			oldestFirst: true,
			limit: 50
		)

		#expect(query.queryItems == [
			URLQueryItem(name: "types", value: "WORKING"),
			URLQueryItem(name: "agentName", value: "factory"),
			URLQueryItem(name: "parentProcessId", value: "4"),
			URLQueryItem(name: "tag", value: "ticket:MOB-1"),
			URLQueryItem(name: "tag", value: "repo:ios"),
			URLQueryItem(name: "order", value: "asc"),
			URLQueryItem(name: "limit", value: "50"),
			URLQueryItem(name: "offset", value: "0"),
		])
	}
}
