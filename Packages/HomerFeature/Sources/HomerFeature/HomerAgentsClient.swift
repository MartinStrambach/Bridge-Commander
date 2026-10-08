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
	/// Starts the agent now as its cron would. Admins only. Returns before the run exists, and
	/// a fire the scheduler refuses starts nothing without failing.
	public var fireCron: @Sendable (_ baseURL: String, _ agentName: String) async throws -> Void
}

extension HomerAgentsClient: DependencyKey {
	public static let liveValue = HomerAgentsClient(
		agents: { try await HomerAPI.agents(baseURL: $0) },
		reload: { try await HomerAPI.reloadAgents(baseURL: $0) },
		run: { try await HomerAPI.runAgent(baseURL: $0, name: $1, request: $2) },
		fireCron: { try await HomerAPI.fireAgentCron(baseURL: $0, name: $1) }
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

	/// `POST /api/v1/agents/{name}/cron-run` (Homer 1.31, ADR-0080): source `cron`, owner
	/// `system:cron`, no inputs, the cron tick's own preflights. Answers 204 with no body even
	/// when a preflight (cost cap, cooldown, lock, parallel-run cap) starts nothing — that is
	/// only logged, as on a tick — and 404 to a non-admin as for an unknown agent. The run's id
	/// shows up later as the agent's `cron.lastRunProcessId`.
	static func fireAgentCron(baseURL: String, name: String) async throws {
		_ = try await send(
			"POST",
			"/api/v1/agents/" + HomerAgent.encodeURIComponent(name) + "/cron-run",
			baseURL: baseURL,
			refusalsInServerWords: true
		)
	}
}
