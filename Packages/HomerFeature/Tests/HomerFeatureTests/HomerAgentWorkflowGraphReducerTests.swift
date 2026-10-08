import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer agent workflow graph", .dependencies)
struct HomerAgentWorkflowGraphReducerTests {
	private nonisolated static let baseURL = "https://homer.example.com"
	private nonisolated static let graph = HomerAgentWorkflowGraph(
		label: "workflow",
		module: "factory_graph.graph",
		topology: .init(
			nodes: [.init(id: "__start__"), .init(id: "plan"), .init(id: "__end__")],
			edges: [.init(source: "__start__", target: "plan"), .init(source: "plan", target: "__end__")]
		)
	)

	@Test("each LangGraph command's graph decodes: a topology, or why there is none")
	func decodes() throws {
		let json = """
			[
			  { "label": "workflow", "module": "factory_graph.graph",
			    "topology": { "nodes": [{ "id": "__start__" }, { "id": "plan" }, { "id": "__end__" }],
			                  "edges": [{ "source": "__start__", "target": "plan" }, { "source": "plan", "target": "__end__" }] },
			    "mermaid": "graph TD;" },
			  { "label": "nightly", "module": "nightly.graph", "error": "busy" }
			]
			"""

		let graphs = try JSONDecoder().decode([HomerAgentWorkflowGraph].self, from: Data(json.utf8))

		#expect(graphs == [Self.graph, HomerAgentWorkflowGraph(label: "nightly", module: "nightly.graph", error: "busy")])
	}

	@Test("opening the sheet reads the agent's graphs; Refresh reads them again")
	func loads() async {
		let calls = LockIsolated(0)
		let store = TestStore(initialState: HomerAgentWorkflowGraphReducer.State(baseURL: Self.baseURL, agentName: "factory")) {
			HomerAgentWorkflowGraphReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].workflowGraphs = { baseURL, agentName in
				#expect(baseURL == Self.baseURL)
				#expect(agentName == "factory")
				calls.withValue { $0 += 1 }
				return [Self.graph]
			}
		}

		await store.send(.task) {
			$0.isLoading = true
		}
		await store.receive(\.graphsLoaded) {
			$0.isLoading = false
			$0.graphs = [Self.graph]
		}
		await store.send(.refreshTapped) {
			$0.isLoading = true
		}
		await store.receive(\.graphsLoaded) {
			$0.isLoading = false
		}
		#expect(calls.value == 2)
	}

	@Test("a failure says why and keeps no graphs; a 404 means the agent is gone")
	func failure() async {
		let store = TestStore(initialState: HomerAgentWorkflowGraphReducer.State(baseURL: Self.baseURL, agentName: "factory")) {
			HomerAgentWorkflowGraphReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].workflowGraphs = { _, _ in
				throw HomerAPIError.server(status: 404, message: "Not Found")
			}
		}

		await store.send(.task) {
			$0.isLoading = true
		}
		await store.receive(\.graphsLoaded) {
			$0.isLoading = false
			$0.loadError = "factory is no longer loaded."
		}
	}

	@Test("an expired session signs the instance out")
	func unauthorized() async {
		let store = TestStore(initialState: HomerAgentWorkflowGraphReducer.State(baseURL: Self.baseURL, agentName: "factory")) {
			HomerAgentWorkflowGraphReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].workflowGraphs = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.task) {
			$0.isLoading = true
		}
		await store.receive(\.graphsLoaded) {
			$0.isLoading = false
		}
		await store.receive(\.delegate, .unauthorized)
	}

	@Test("the agents page opens an agent's graph sheet, and a 401 in it closes it and signs out")
	func agentsPagePresentsSheet() async {
		let store = TestStore(initialState: HomerAgentsReducer.State(baseURL: Self.baseURL)) {
			HomerAgentsReducer()
		} withDependencies: {
			$0[HomerAgentsClient.self].workflowGraphs = { _, _ in throw HomerAPIError.unauthorized }
		}

		await store.send(.workflowGraphTapped(agentName: "factory")) {
			$0.workflowGraph = HomerAgentWorkflowGraphReducer.State(baseURL: Self.baseURL, agentName: "factory")
		}
		await store.send(.workflowGraph(.presented(.task))) {
			$0.workflowGraph?.isLoading = true
		}
		await store.receive(\.workflowGraph.presented.graphsLoaded) {
			$0.workflowGraph?.isLoading = false
		}
		await store.receive(\.workflowGraph.presented.delegate, .unauthorized) {
			$0.workflowGraph = nil
		}
		await store.receive(\.delegate, .unauthorized)
	}
}
