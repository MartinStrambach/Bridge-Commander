import ComposableArchitecture
import Foundation

/// The agent calls of the Agents and Schedules pages, addressed by the instance's base URL.
/// Errors are `HomerAPIError`s.
@DependencyClient
public struct HomerAgentsClient: Sendable {
	/// The agents the user holds any grant on, in the server's order.
	public var agents: @Sendable (_ baseURL: String) async throws -> [HomerAgent]
	/// Re-reads every agent definition from disk. Admins only.
	public var reload: @Sendable (_ baseURL: String) async throws -> HomerAgentReloadResult
	/// Starts a run and returns its process id.
	public var run: @Sendable (_ baseURL: String, _ agentName: String, _ request: HomerAgentRunRequest) async throws -> Int
}

extension HomerAgentsClient: DependencyKey {
	public static let liveValue = HomerAgentsClient(
		agents: { try await HomerAPI.agents(baseURL: $0) },
		reload: { try await HomerAPI.reloadAgents(baseURL: $0) },
		run: { try await HomerAPI.runAgent(baseURL: $0, name: $1, request: $2) }
	)
}

extension HomerAgentsClient: TestDependencyKey {
	public static let testValue = HomerAgentsClient()
}

extension HomerAPI {
	static func agents(baseURL: String) async throws -> [HomerAgent] {
		try await decode(HomerAgentListResponse.self, from: send("GET", "/api/v1/agents", baseURL: baseURL)).agents
	}

	static func reloadAgents(baseURL: String) async throws -> HomerAgentReloadResult {
		try await decode(HomerAgentReloadResult.self, from: send("POST", "/api/v1/agents/reload", baseURL: baseURL))
	}

	/// The inputs may include request headers, and the run's refusals (409 another run still
	/// active, 429 a cost cap, cooldown or parallel-run limit) are told in the server's words.
	static func runAgent(baseURL: String, name: String, request: HomerAgentRunRequest) async throws -> Int {
		let data = try await send(
			"POST",
			HomerAgentRunRequest.path(agentName: name),
			baseURL: baseURL,
			percentEncodedQueryItems: request.percentEncodedQueryItems,
			headers: request.headers.map { (name: $0.name, value: $0.value) },
			body: request.bodyJSON,
			refusalsInServerWords: true
		)
		return try decode(HomerAgentRunResponse.self, from: data).processId
	}
}
