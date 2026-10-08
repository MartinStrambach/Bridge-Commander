import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer instance pages", .dependencies)
struct HomerChildPageTests {
	private static let baseURL = "https://homer.example.com"

	private func activeState(user: HomerUser) -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedIn(user)
		state.isActive = true
		return state
	}

	@Test("a page reducer is told when it comes on screen and when it leaves")
	func shownAndHidden() async {
		let initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		let agent = HomerAgent(name: "factory")
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerContinuationsClient.self].continuations = { _, _ in [] }
			$0[HomerAgentsClient.self].agents = { _ in [agent] }
		}

		await store.send(.pageChanged(.continuations)) {
			$0.page = .continuations
			$0.shownChildPage = .continuations
		}
		await store.receive(\.continuations.shown) {
			$0.continuations.isShown = true
		}
		await store.receive(\.continuations.loaded.success) {
			$0.continuations.hasLoaded = true
		}

		await store.send(.pageChanged(.agents)) {
			$0.page = .agents
			$0.shownChildPage = .agents
		}
		await store.receive(\.continuations.hidden) {
			$0.continuations.isShown = false
		}
		await store.receive(\.agents.shown) {
			$0.agents.shownPage = .agents
		}
		await store.receive(\.agents.agentsLoaded) {
			$0.agents.agents = [agent]
			$0.agents.hasLoaded = true
		}
		// Agents and Schedules are one reducer, told which of the two is on screen (an agent's
		// page shows in place of either).
		await store.send(.pageChanged(.schedules)) {
			$0.page = .schedules
			$0.shownChildPage = .schedules
		}
		await store.receive(\.agents.hidden) {
			$0.agents.shownPage = nil
		}
		await store.receive(\.agents.shown) {
			$0.agents.shownPage = .schedules
		}
		await store.receive(\.agents.agentsLoaded)

		await store.send(.deactivated) {
			$0.isActive = false
			$0.shownChildPage = nil
		}
		await store.receive(\.agents.hidden) {
			$0.agents.shownPage = nil
		}
	}

	@Test("the header's Refresh reaches the page on screen")
	func refreshReachesPage() async {
		var initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		initialState.page = .continuations
		initialState.shownChildPage = .continuations
		initialState.continuations.isShown = true
		let fetches = LockIsolated(0)
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
			$0[HomerClient.self].openQuestions = { _ in [] }
			$0[HomerContinuationsClient.self].pendingCount = { _ in 0 }
			$0[HomerContinuationsClient.self].continuations = { _, _ in
				fetches.withValue { $0 += 1 }
				return []
			}
		}

		// The processes and questions are refreshed too; this test is about the page.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.refreshTapped)
		await store.receive(\.continuations.refreshTapped)
		await store.receive(\.continuations.loaded.success)
		// Both lists, pending and failed.
		#expect(fetches.value == 2)
		await store.skipInFlightEffects()
	}

	@Test("an admin-only page stays hidden for anyone else")
	func adminOnly() async {
		let initialState = activeState(user: HomerUser(username: "dev"))
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.pageChanged(.costs)) {
			$0.page = .costs
		}
	}

	@Test("a page's 401 signs the instance out, and its poll stops")
	func pageUnauthorized() async {
		var initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		initialState.page = .costs
		initialState.shownChildPage = .costs
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.costs(.delegate(.unauthorized))) {
			$0.session = .signedOut
			$0.signIn.sessionExpired = true
			$0.shownChildPage = nil
		}
		await store.receive(\.costs.hidden)
	}

	@Test("a page opens a run natively")
	func pageOpensProcess() async {
		let user = HomerUser(username: "admin", role: "admin")
		let initialState = activeState(user: user)
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		}

		await store.send(.continuations(.delegate(.openProcess(processId: 12))))
		await store.receive(\.processTapped) {
			$0.processDetail = HomerProcessDetailReducer.State(baseURL: Self.baseURL, processId: 12, user: user)
		}
	}

	@Test("a page opens the web console in the instance's sheet")
	func pageOpensWebConsole() async {
		let initialState = activeState(user: HomerUser(username: "admin", role: "admin"))
		let store = TestStore(initialState: initialState) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerClient.self].sessionCookies = { _ in [] }
		}

		await store.send(.agents(.delegate(.openWebConsole(path: "agents/factory", title: "factory"))))
		await store.receive(\.openWebConsoleTapped) {
			$0.webPage = HomerWebPage(
				url: URL(string: "https://homer.example.com/agents/factory")!,
				title: "factory",
				cookies: [],
				dataStoreID: HomerEndpoint.webDataStoreID(baseURL: Self.baseURL)
			)
		}
	}
}
