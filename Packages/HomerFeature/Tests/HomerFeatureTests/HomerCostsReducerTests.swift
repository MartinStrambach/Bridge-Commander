import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer costs page", .dependencies)
struct HomerCostsReducerTests {
	private static let baseURL = "https://homer.example.com"

	private let snapshot = HomerCostSnapshot(
		globalUsdLast60s: 0.04,
		globalCapUsdPerMin: 0.5,
		perAgentUsdLast24h: ["factory": 9.5],
		perAgentCapUsdPerDay: ["factory": 10],
		snapshotAtSec: 1_783_420_800
	)
	private let october = HomerMonthlyCosts(
		month: "2026-10",
		perAgentUsd: ["factory": 1.25],
		totalUsd: 1.25,
		availableMonths: ["2026-10", "2026-09", "2026-08"]
	)
	private let september = HomerMonthlyCosts(
		month: "2026-09",
		perAgentUsd: ["factory": 4],
		totalUsd: 4,
		availableMonths: ["2026-10", "2026-09", "2026-08"]
	)
	private let august = HomerMonthlyCosts(
		month: "2026-08",
		perAgentUsd: ["planner": 2],
		totalUsd: 2,
		availableMonths: ["2026-10", "2026-09", "2026-08"]
	)
	private let totals = HomerTotalCosts(perAgentUsd: ["factory": 14.75, "planner": 2], totalUsd: 16.75)

	private func loadedState() -> HomerCostsReducer.State {
		var state = HomerCostsReducer.State(baseURL: Self.baseURL)
		state.isShown = true
		state.snapshot = snapshot
		state.monthly = october
		state.totals = totals
		return state
	}

	/// Lets the effects started so far deliver their answers, then takes them in.
	private func settle(_ store: TestStoreOf<HomerCostsReducer>) async {
		for _ in 0 ..< 10 {
			await Task.yield()
		}
		await store.skipReceivedActions(strict: false)
	}

	@Test("coming on screen loads all three, then polls each on the console's cadence until hidden")
	func shownPollsUntilHidden() async {
		let clock = TestClock()
		let calls = LockIsolated<[String]>([])
		let store = TestStore(initialState: HomerCostsReducer.State(baseURL: Self.baseURL)) {
			HomerCostsReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerCostsClient.self].snapshot = { baseURL in
				calls.withValue { $0.append("snapshot \(baseURL)") }
				return snapshot
			}
			$0[HomerCostsClient.self].monthly = { _, month in
				calls.withValue { $0.append("monthly \(month ?? "current")") }
				return october
			}
			$0[HomerCostsClient.self].totals = { _ in
				calls.withValue { $0.append("totals") }
				return totals
			}
		}

		// The three loops start together, and which answers first is the scheduler's business:
		// the answers' effects are checked, not their order.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.shown) {
			$0.isShown = true
		}
		await settle(store)
		#expect(store.state.snapshot == snapshot)
		#expect(store.state.monthly == october)
		#expect(store.state.totals == totals)
		#expect(calls.value.sorted() == ["monthly current", "snapshot \(Self.baseURL)", "totals"])

		calls.setValue([])
		await clock.advance(by: .seconds(5))
		await settle(store)
		#expect(calls.value == ["snapshot \(Self.baseURL)"])

		// At 30 s the ledger is read again, alongside the snapshot's sixth read.
		await clock.advance(by: .seconds(25))
		await settle(store)
		#expect(calls.value.count(where: { $0.hasPrefix("snapshot") }) == 6)
		#expect(calls.value.filter { !$0.hasPrefix("snapshot") }.sorted() == ["monthly current", "totals"])
		store.exhaustivity = .on

		// Exhaustive again: the test fails if a loop is still running when it ends.
		await store.send(.hidden) {
			$0.isShown = false
		}
		calls.setValue([])
		await clock.advance(by: .seconds(60))
		#expect(calls.value.isEmpty)
	}

	@Test("picking a month reads it, and an older month's late answer never lands")
	func monthChangeDropsStaleAnswer() async {
		let clock = TestClock()
		let store = TestStore(initialState: loadedState()) {
			HomerCostsReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerCostsClient.self].monthly = { [september, august] _, month in
				// September's ledger answers slowly; August's at once.
				guard month == "2026-09" else {
					return august
				}
				try await clock.sleep(for: .seconds(3))
				return september
			}
		}

		await store.send(.monthSelected("2026-09")) {
			$0.selectedMonth = "2026-09"
		}
		#expect(store.state.isMonthlyCurrent == false)
		#expect(store.state.shownMonth == "2026-09")

		await store.send(.monthSelected("2026-08")) {
			$0.selectedMonth = "2026-08"
		}
		await store.receive(\.monthlyLoaded) {
			$0.monthly = august
		}
		#expect(store.state.isMonthlyCurrent)

		// September's request was cancelled with its loop: nothing arrives when it would have.
		await clock.advance(by: .seconds(3))

		// An answer for a month no longer picked is dropped even if it gets through.
		await store.send(.monthlyLoaded(month: "2026-09", .success(september)))

		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("picking the month on screen reads nothing again")
	func reselectingShownMonth() async {
		let store = TestStore(initialState: loadedState()) {
			HomerCostsReducer()
		}

		await store.send(.monthSelected("2026-10"))
	}

	@Test("a failed refresh keeps the last data under a banner, until the next one succeeds")
	func failedRefreshKeepsData() async {
		let clock = TestClock()
		let failing = LockIsolated(true)
		let store = TestStore(initialState: loadedState()) {
			HomerCostsReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerCostsClient.self].snapshot = { _ in
				if failing.value {
					throw HomerAPIError.unreachable("offline")
				}
				return snapshot
			}
			$0[HomerCostsClient.self].monthly = { _, _ in throw HomerAPIError.unreachable("offline") }
			$0[HomerCostsClient.self].totals = { _ in throw HomerAPIError.unreachable("offline") }
		}
		let message = HomerAPIError.unreachable("offline").localizedDescription

		// Shown again after being hidden: the data from before is still there.
		await store.send(.hidden) {
			$0.isShown = false
		}
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.shown) {
			$0.isShown = true
		}
		await settle(store)
		#expect(store.state.snapshotError == message)
		#expect(store.state.monthlyError == message)
		#expect(store.state.totalsError == message)
		#expect(store.state.errorMessages == [message])
		#expect(store.state.snapshot == snapshot)
		#expect(store.state.monthly == october)
		#expect(store.state.totals == totals)
		#expect(store.state.isLoading == false)
		store.exhaustivity = .on

		failing.setValue(false)
		await clock.advance(by: .seconds(5))
		await store.receive(\.snapshotLoaded) {
			$0.snapshotError = nil
		}

		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a 401 stops the page and tells the instance its session ended")
	func unauthorized() async {
		let store = TestStore(initialState: HomerCostsReducer.State(baseURL: Self.baseURL)) {
			HomerCostsReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerCostsClient.self].snapshot = { _ in throw HomerAPIError.unauthorized }
			// The other two never answer before the page is stopped.
			$0[HomerCostsClient.self].monthly = { _, _ in
				try await Task.never()
			}
			$0[HomerCostsClient.self].totals = { _ in
				try await Task.never()
			}
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.snapshotLoaded) {
			$0.isShown = false
		}
		await store.receive(\.delegate)
	}
}
