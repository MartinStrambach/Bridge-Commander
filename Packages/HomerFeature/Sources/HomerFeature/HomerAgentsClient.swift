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

	/// Starts a run through `sendRun`, not `send`: the inputs may include request headers,
	/// which `send` cannot carry, and the run's refusals (409 another run still active, 429 a
	/// cost cap, cooldown or parallel-run limit) need the server's own words, which `send` maps
	/// to the question and login-limiter messages.
	static func runAgent(baseURL: String, name: String, request: HomerAgentRunRequest) async throws -> Int {
		let data = try await sendRun(
			HomerAgentRunRequest.path(agentName: name),
			baseURL: baseURL,
			percentEncodedQueryItems: request.percentEncodedQueryItems,
			body: request.bodyJSON,
			headers: request.headers
		)
		return try decode(HomerAgentRunResponse.self, from: data).processId
	}

	// MARK: - Transport of a run

	/// `URLSession` for `sendRun`, configured as `send`'s: cookies are the jar's alone.
	private static let runSession: URLSession = {
		let configuration = URLSessionConfiguration.default
		configuration.httpCookieStorage = nil
		configuration.httpCookieAcceptPolicy = .never
		configuration.httpShouldSetCookies = false
		return URLSession(configuration: configuration)
	}()

	/// A `POST` as `send` makes it (the same cookie jar and CSRF header) plus request headers,
	/// with every refusal but 401 and 403 reported in the server's words.
	private static func sendRun(
		_ path: String,
		baseURL: String,
		percentEncodedQueryItems: [URLQueryItem],
		body: Data?,
		headers: [HomerAgentRunRequest.Field]
	) async throws -> Data {
		guard var components = URLComponents(string: baseURL + path) else {
			throw HomerAPIError.unexpectedResponse
		}
		if !percentEncodedQueryItems.isEmpty {
			components.percentEncodedQueryItems = percentEncodedQueryItems
		}
		guard let url = components.url else {
			throw HomerAPIError.unexpectedResponse
		}

		var request = URLRequest(url: url, timeoutInterval: 30)
		request.httpMethod = "POST"
		request.httpBody = body
		// The inputs first, so none of them can replace what the API needs.
		for header in headers {
			request.setValue(header.value, forHTTPHeaderField: header.name)
		}
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("1", forHTTPHeaderField: "X-Homer-CSRF")
		if body != nil {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		let jar = HomerCookieJar.shared
		for (field, value) in HTTPCookie.requestHeaderFields(with: jar.cookies(for: baseURL)) {
			request.setValue(value, forHTTPHeaderField: field)
		}

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await runSession.data(for: request)
		}
		catch {
			throw HomerAPIError.unreachable(error.localizedDescription)
		}
		guard let http = response as? HTTPURLResponse else {
			throw HomerAPIError.unexpectedResponse
		}
		jar.update(for: baseURL, from: http)
		switch http.statusCode {
		case 200 ..< 300:
			return data
		case 401:
			throw HomerAPIError.unauthorized
		case 403:
			throw HomerAPIError.forbidden
		default:
			struct ErrorBody: Decodable {
				var msg: String?
			}
			guard let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.msg else {
				throw http.statusCode == 429 ? HomerAPIError.rateLimited : HomerAPIError.server(status: http.statusCode, message: nil)
			}
			throw HomerAPIError.server(status: http.statusCode, message: message)
		}
	}
}
