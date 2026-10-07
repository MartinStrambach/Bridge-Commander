import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer cost models")
struct HomerCostModelsTests {
	/// The shape of the server's `CostsResponse`, with a field the app does not read.
	private let snapshotJSON = """
		{
		  "globalUsdLast60s": 0.0421,
		  "globalCapUsdPerMin": 0.5,
		  "perAgentUsdLast24h": { "reviewer": 2.0, "factory": 9.5 },
		  "perAgentCapUsdPerDay": { "factory": 10.0, "planner": 3.0 },
		  "snapshotAtSec": 1783420800,
		  "somethingNewer": true
		}
		"""

	@Test("a cost snapshot decodes, unknown fields ignored")
	func decodesSnapshot() throws {
		let snapshot = try JSONDecoder().decode(HomerCostSnapshot.self, from: Data(snapshotJSON.utf8))

		#expect(snapshot.globalUsdLast60s == 0.0421)
		#expect(snapshot.globalCapUsdPerMin == 0.5)
		#expect(snapshot.perAgentUsdLast24h == ["reviewer": 2.0, "factory": 9.5])
		#expect(snapshot.perAgentCapUsdPerDay == ["factory": 10.0, "planner": 3.0])
		#expect(snapshot.snapshotAtSec == 1_783_420_800)
	}

	@Test("a snapshot without a global cap or any agent decodes")
	func decodesBareSnapshot() throws {
		let json = #"{ "globalUsdLast60s": 0, "globalCapUsdPerMin": null, "snapshotAtSec": 1 }"#
		let snapshot = try JSONDecoder().decode(HomerCostSnapshot.self, from: Data(json.utf8))

		#expect(snapshot.globalCapUsdPerMin == nil)
		#expect(snapshot.agentUsages.isEmpty)
	}

	@Test("a page that is not Homer's answer does not decode as a snapshot")
	func rejectsOtherJSON() {
		#expect(throws: (any Error).self) {
			try JSONDecoder().decode(HomerCostSnapshot.self, from: Data(#"{ "processes": [] }"#.utf8))
		}
	}

	@Test("the per-agent table lists every agent with spend or a cap, sorted")
	func agentUsages() throws {
		let snapshot = try JSONDecoder().decode(HomerCostSnapshot.self, from: Data(snapshotJSON.utf8))

		#expect(snapshot.agentUsages == [
			.init(agentName: "factory", spentUsd: 9.5, capUsd: 10),
			.init(agentName: "planner", spentUsd: 0, capUsd: 3),
			.init(agentName: "reviewer", spentUsd: 2, capUsd: nil),
		])
	}

	@Test("a month of the ledger decodes into sorted rows")
	func decodesMonthly() throws {
		// The example in the server's README.
		let json = """
			{
			  "month": "2026-07",
			  "perAgentUsd": { "reviewer": 2.0, "planner": 0.5 },
			  "totalUsd": 2.5,
			  "availableMonths": ["2026-07", "2026-06"]
			}
			"""
		let monthly = try JSONDecoder().decode(HomerMonthlyCosts.self, from: Data(json.utf8))

		#expect(monthly.month == "2026-07")
		#expect(monthly.totalUsd == 2.5)
		#expect(monthly.rows == [
			HomerAgentCost(agentName: "planner", usd: 0.5),
			HomerAgentCost(agentName: "reviewer", usd: 2.0),
		])
		#expect(monthly.pickerMonths == ["2026-07", "2026-06"])
	}

	@Test("a month without entries is still among the picker's months, newest first")
	func pickerMonthsIncludeShownMonth() {
		let monthly = HomerMonthlyCosts(month: "2026-10", totalUsd: 0, availableMonths: ["2026-09", "2026-07"])

		#expect(monthly.rows.isEmpty)
		#expect(monthly.pickerMonths == ["2026-10", "2026-09", "2026-07"])
	}

	@Test("all-time totals decode into sorted rows")
	func decodesTotals() throws {
		let json = #"{ "perAgentUsd": { "reviewer": 3.0, "planner": 0.5 }, "totalUsd": 3.5 }"#
		let totals = try JSONDecoder().decode(HomerTotalCosts.self, from: Data(json.utf8))

		#expect(totals.totalUsd == 3.5)
		#expect(totals.rows.map(\.agentName) == ["planner", "reviewer"])
	}

	@Test("usage against a cap", arguments: [
		(2.5, 10.0, 25.0, "25%", HomerCostUsage.Level.normal),
		(8.0, 10.0, 80.0, "80%", .nearCap),
		(10.0, 10.0, 100.0, "100%", .overCap),
		(15.0, 10.0, 100.0, "100%", .overCap),
		(1.0, 0.0, 0.0, "0%", .normal),
		(0.125, 1.0, 12.5, "13%", .normal),
	])
	func usage(spent: Double, cap: Double, percent: Double, text: String, level: HomerCostUsage.Level) {
		let usage = HomerCostUsage(spentUsd: spent, capUsd: cap)

		#expect(usage.percent == percent)
		#expect(usage.percentText == text)
		#expect(usage.level == level)
	}

	@Test("a ledger month reads as its name")
	func monthTitle() {
		let english = Locale(identifier: "en_US")

		#expect(HomerFormat.month("2026-07", locale: english) == "July 2026")
		#expect(HomerFormat.month("2026-01", locale: english) == "January 2026")
		#expect(HomerFormat.month("July", locale: english) == "July")
	}
}
