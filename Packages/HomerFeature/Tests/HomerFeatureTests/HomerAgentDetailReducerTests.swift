import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer agent page", .dependencies)
struct HomerAgentDetailReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private let factory = HomerAgent(name: "factory", inputs: [HomerAgent.Input(paramName: "ticket")])
	private let nightly = HomerAgent(
		name: "Nightly",
		cron: HomerAgent.Cron(expression: "0 3 * * *", timezone: "UTC")
	)
	private let run = HomerProcess(id: 7, status: .working, agentName: "factory", costUsd: 0.25)

	private func agentsState(shownPage: HomerAgentsReducer.Page? = .agents) -> HomerAgentsReducer.State {
		var state = HomerAgentsReducer.State(baseURL: Self.baseURL)
		state.agents = [factory, nightly]
		state.hasLoaded = true
		state.shownPage = shownPage
		return state
	}

	private func detailState() -> HomerAgentDetailReducer.State {
		var state = HomerAgentDetailReducer.State(baseURL: Self.baseURL, agentName: "factory", agent: factory)
		state.isShown = true
		return state
	}

	// MARK: - On the Agents page

	@Test("an agent opens its page in place of the cards, which polls the agent's runs until hidden")
	func opensInPlace() async {
		let clock = TestClock()
		let queries = LockIsolated<[HomerProcessQuery]>([])
		let store = TestStore(initialState: agentsState()) {
			HomerAgentsReducer()
		} withDependencies: { [run] in
			$0.continuousClock = clock
			$0[HomerClient.self].processes = { baseURL, query in
				#expect(baseURL == Self.baseURL)
				queries.withValue { $0.append(query) }
				return HomerProcessPage(processes: [run], total: 1)
			}
		}

		await store.send(.agentTapped(agentName: "factory")) {
			$0.detail = HomerAgentDetailReducer.State(
				baseURL: Self.baseURL,
				agentName: "factory",
				openedFrom: .agents,
				agent: factory
			)
		}
		await store.receive(\.detail.shown) {
			$0.detail?.isShown = true
		}
		await store.receive(\.detail.runsLoaded) {
			$0.detail?.runs = [run]
			$0.detail?.runTotal = 1
			$0.detail?.hasLoadedRuns = true
		}
		#expect(queries.value == [HomerProcessQuery(agentName: "factory", limit: HomerAgentDetailReducer.pageSize)])
		await clock.advance(by: HomerAgentDetailReducer.pollInterval)
		await store.receive(\.detail.runsLoaded)

		await store.send(.hidden) {
			$0.shownPage = nil
			$0.detail?.isShown = false
		}
		await clock.advance(by: HomerAgentDetailReducer.pollInterval * 3)
		#expect(queries.value.count == 2)
	}

	@Test("the page polls only while the page that opened it is on screen")
	func followsItsPage() async {
		let clock = TestClock()
		var initialState = agentsState(shownPage: nil)
		initialState.detail = HomerAgentDetailReducer.State(
			baseURL: Self.baseURL,
			agentName: "Nightly",
			openedFrom: .schedules,
			agent: nightly
		)
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		} withDependencies: { [factory, nightly] in
			$0.continuousClock = clock
			$0[HomerAgentsClient.self].agents = { _ in [factory, nightly] }
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
		}

		// The Agents page shows its cards; the schedule's agent page waits.
		await store.send(.shown(.agents)) {
			$0.shownPage = .agents
		}
		await store.receive(\.agentsLoaded)
		await store.send(.hidden) {
			$0.shownPage = nil
		}

		await store.send(.shown(.schedules)) {
			$0.shownPage = .schedules
		}
		await store.receive(\.detail.shown) {
			$0.detail?.isShown = true
		}
		await store.receive(\.agentsLoaded)
		await store.receive(\.detail.runsLoaded) {
			$0.detail?.hasLoadedRuns = true
		}
		await store.send(.hidden) {
			$0.shownPage = nil
			$0.detail?.isShown = false
		}
	}

	@Test("the list's poll keeps the agent current, and one no longer listed reads as not found")
	func agentFollowsList() async {
		var initialState = agentsState()
		initialState.detail = detailState()
		let renamed = HomerAgent(name: "factory", description: "Builds things")
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.agentsLoaded(.success([renamed, nightly]))) {
			$0.agents = [renamed, nightly]
			$0.detail?.agent = renamed
		}
		await store.send(.agentsLoaded(.success([nightly]))) {
			$0.agents = [nightly]
			$0.detail?.agent = nil
		}
	}

	@Test("Back returns to the cards; Run and Edit are the Agents page's own")
	func backRunAndEdit() async {
		var initialState = agentsState()
		initialState.detail = HomerAgentDetailReducer.State(baseURL: Self.baseURL, agentName: "factory", agent: factory)
		let store = TestStore(initialState: initialState) {
			HomerAgentsReducer()
		}

		await store.send(.detail(.runTapped))
		await store.receive(\.detail.delegate, .run)
		await store.receive(\.runTapped) {
			$0.runAgent = HomerRunAgentReducer.State(baseURL: Self.baseURL, agent: factory)
		}
		await store.send(.runAgent(.dismiss)) {
			$0.runAgent = nil
		}

		await store.send(.detail(.editTapped))
		await store.receive(\.detail.delegate, .edit)
		await store.receive(\.editTapped)
		await store.receive(\.delegate, .openWebConsole(path: "agents/factory/edit", title: "Edit factory"))

		await store.send(.detail(.processTapped(processId: 7)))
		await store.receive(\.detail.delegate, .openProcess(processId: 7))
		await store.receive(\.processTapped)
		await store.receive(\.delegate, .openProcess(processId: 7))

		await store.send(.detail(.backTapped))
		await store.receive(\.detail.delegate, .back) {
			$0.detail = nil
		}
	}

	// MARK: - The page itself

	@Test("Load More grows the page and restarts the poll")
	func loadMore() async {
		var initialState = detailState()
		initialState.runs = [run]
		initialState.runTotal = 80
		initialState.hasLoadedRuns = true
		let limits = LockIsolated<[Int]>([])
		let store = TestStore(initialState: initialState) {
			HomerAgentDetailReducer()
		} withDependencies: { [run] in
			$0.continuousClock = TestClock()
			$0[HomerClient.self].processes = { _, query in
				limits.withValue { $0.append(query.limit) }
				return HomerProcessPage(processes: [run], total: 80)
			}
		}

		await store.send(.loadMoreRunsTapped) {
			$0.runLimit = HomerAgentDetailReducer.pageSize * 2
		}
		await store.receive(\.runsLoaded)
		#expect(limits.value == [HomerAgentDetailReducer.pageSize * 2])
		await store.skipInFlightEffects()
	}

	@Test("the workflow graphs are read the first time their section is shown")
	func workflowOnFirstShow() async {
		let graph = HomerAgentWorkflowGraph(label: "build", error: "busy")
		let calls = LockIsolated(0)
		let store = TestStore(initialState: detailState()) {
			HomerAgentDetailReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].workflowGraphs = { _, name in
				#expect(name == "factory")
				calls.withValue { $0 += 1 }
				return [graph]
			}
		}

		await store.send(.sectionSelected(.workflow)) {
			$0.section = .workflow
		}
		await store.receive(\.workflowGraph.task) {
			$0.workflowGraph.isLoading = true
		}
		await store.receive(\.workflowGraph.graphsLoaded) {
			$0.workflowGraph.isLoading = false
			$0.workflowGraph.graphs = [graph]
		}
		await store.send(.sectionSelected(.runs)) {
			$0.section = .runs
		}
		await store.send(.sectionSelected(.workflow)) {
			$0.section = .workflow
		}
		#expect(calls.value == 1)
	}

	@Test("Kill asks first, then refetches the runs")
	func kill() async {
		let killed = LockIsolated<[Int]>([])
		let store = TestStore(initialState: detailState()) {
			HomerAgentDetailReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerClient.self].killProcess = { _, id in killed.withValue { $0.append(id) } }
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
		}

		await store.send(.killTapped(processId: 7)) {
			$0.alert = AlertState {
				TextState("Kill process #7?")
			} actions: {
				ButtonState(role: .destructive, action: .killConfirmed(processId: 7)) {
					TextState("Kill Process")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState("This cannot be undone.")
			}
		}
		await store.send(.alert(.presented(.killConfirmed(processId: 7)))) {
			$0.alert = nil
			$0.runActionsInFlight = [7]
		}
		await store.receive(\.runActionFinished) {
			$0.runActionsInFlight = []
		}
		await store.receive(\.runsLoaded) {
			$0.hasLoadedRuns = true
		}
		#expect(killed.value == [7])
		await store.skipInFlightEffects()
	}

	@Test("a retry opens the new run")
	func retry() async {
		var initialState = detailState()
		initialState.isShown = false
		let store = TestStore(initialState: initialState) {
			HomerAgentDetailReducer()
		} withDependencies: {
			$0[HomerClient.self].retryProcess = { _, _ in 8 }
		}

		await store.send(.retryTapped(processId: 7)) {
			$0.runActionsInFlight = [7]
		}
		await store.receive(\.runActionFinished) {
			$0.runActionsInFlight = []
		}
		await store.receive(\.delegate, .openProcess(processId: 8))
	}

	@Test("a 401 asks the instance to sign out")
	func unauthorized() async {
		let store = TestStore(initialState: detailState()) {
			HomerAgentDetailReducer()
		}

		await store.send(.runsLoaded(.failure(HomerAPIError.unauthorized)))
		await store.receive(\.delegate, .unauthorized)
	}
}
