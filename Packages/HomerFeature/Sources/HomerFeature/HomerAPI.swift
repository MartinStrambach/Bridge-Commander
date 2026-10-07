import Foundation
import Synchronization

/// Why a Homer call failed, classified the way the web console tells its user (`auth-context.tsx`,
/// `question-item.tsx`): a 401 is a missing or expired session (or, from the login call, a wrong
/// password), a 429 is the login limiter, a 409 a question someone already answered.
public nonisolated enum HomerAPIError: Error, Equatable, LocalizedError {
	case unauthorized
	case forbidden
	case rateLimited
	case conflict
	case server(status: Int, message: String?)
	case unreachable(String)
	case unexpectedResponse

	public var errorDescription: String? {
		switch self {
		case .unauthorized:
			"Not signed in."
		case .forbidden:
			"Your Homer account is not allowed to do this."
		case .rateLimited:
			"Too many requests. Please wait a moment and try again."
		case .conflict:
			"This question is no longer open — it was answered elsewhere or expired."
		case let .server(status, message):
			message ?? "The server answered with HTTP \(status)."
		case let .unreachable(reason):
			"Could not reach the server: \(reason)"
		case .unexpectedResponse:
			"The server's answer was not what a Homer instance returns. Check the instance URL."
		}
	}
}

/// The live calls behind `HomerClient`. Authentication is the console's cookie mode: the login
/// call answers with an `HttpOnly` session cookie (`homer_session`, 12 h by default), sent back
/// on every later call. Cookies are kept per instance in `HomerCookieJar`, not by `URLSession`,
/// so several instances stay signed in side by side.
nonisolated enum HomerAPI {
	/// The backend's CSRF guard rejects a cookie-authenticated request without this header
	/// (Homer ADR-0016); the console sends it on every call, and so does this.
	private static let csrfHeader = "X-Homer-CSRF"
	private static let timeout: TimeInterval = 30

	private static let jar = HomerCookieJar.shared

	private static let sessions = Mutex<[String: URLSession]>([:])

	/// One session per instance. Instances on one ingress share its IP and wildcard certificate,
	/// and a single session would coalesce their HTTP/2 connections — one instance's requests
	/// riding another's, which the ingress refuses with 421 Misdirected Request. Sessions never
	/// share connections. Leaves cookies to `jar`: it neither stores nor sends any of its own.
	private static func session(for baseURL: String) -> URLSession {
		sessions.withLock { sessions in
			if let session = sessions[baseURL] {
				return session
			}
			let configuration = URLSessionConfiguration.default
			configuration.httpCookieStorage = nil
			configuration.httpCookieAcceptPolicy = .never
			configuration.httpShouldSetCookies = false
			let session = URLSession(configuration: configuration)
			sessions[baseURL] = session
			return session
		}
	}

	static func me(baseURL: String) async throws -> HomerUser {
		try await decode(HomerUser.self, from: send("GET", "/api/v1/auth/me", baseURL: baseURL))
	}

	/// Signs in and returns who the session belongs to. The login answer only names the user, so
	/// `/me` is read afterwards for the role, as the console does.
	static func login(baseURL: String, username: String, password: String) async throws -> HomerUser {
		let body = try JSONEncoder().encode(["username": username, "password": password])
		_ = try await send("POST", "/api/v1/auth/login", baseURL: baseURL, body: body)
		return try await me(baseURL: baseURL)
	}

	/// Ends the session on the server, then drops the instance's cookies locally too — the
	/// app's and the embedded web console's: the logout answer clears the cookie, but a call that
	/// never reaches the server must still leave the app signed out.
	static func logout(baseURL: String) async throws {
		do {
			_ = try await send("POST", "/api/v1/auth/logout", baseURL: baseURL)
		}
		catch {
			await forgetSession(baseURL: baseURL)
			throw error
		}
		await forgetSession(baseURL: baseURL)
	}

	private static func forgetSession(baseURL: String) async {
		jar.removeAll(for: baseURL)
		await HomerWebDataStore.removeCookies(baseURL: baseURL)
	}

	static func processes(baseURL: String, query: HomerProcessQuery) async throws -> HomerProcessPage {
		try await decode(
			HomerProcessPage.self,
			from: send("GET", "/api/v1/status/all", baseURL: baseURL, queryItems: query.queryItems)
		)
	}

	/// The names of the agents the user can see, sorted — the agent filter's choices.
	static func agentNames(baseURL: String) async throws -> [String] {
		let list = try await decode(HomerAgentList.self, from: send("GET", "/api/v1/agents", baseURL: baseURL))
		return list.agents.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
	}

	static func killProcess(baseURL: String, id: Int) async throws {
		_ = try await send("DELETE", "/api/v1/kill/\(id)", baseURL: baseURL)
	}

	/// Starts the run again with its inputs and returns the new run's id.
	static func retryProcess(baseURL: String, id: Int) async throws -> Int {
		try await decode(
			HomerRetryResponse.self,
			from: send("POST", "/api/v1/processes/\(id)/retry", baseURL: baseURL)
		).processId
	}

	static func openQuestions(baseURL: String) async throws -> [HomerQuestion] {
		let data = try await send(
			"GET",
			"/api/v1/questions",
			baseURL: baseURL,
			queryItems: [URLQueryItem(name: "status", value: "OPEN")]
		)
		return try decode(HomerQuestionList.self, from: data).questions
	}

	static func answerQuestion(baseURL: String, id: String, answer: String) async throws {
		let escapedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
		let body = try JSONEncoder().encode(["answer": answer])
		_ = try await send("POST", "/api/v1/questions/\(escapedId)/answer", baseURL: baseURL, body: body)
	}

	/// The cookies held for the instance — handed to the embedded web console so it opens signed
	/// in instead of on its own login page.
	static func sessionCookies(baseURL: String) -> [HTTPCookie] {
		jar.cookies(for: baseURL)
	}

	// MARK: - Transport

	/// - Parameters:
	///   - percentEncodedQueryItems: Query items already percent-encoded, sent as they are —
	///     `queryItems` leaves a `+` alone, which the server reads as a space.
	///   - headers: Request headers of the caller's own. They go on first, so none of them can
	///     replace what the API needs.
	///   - refusalsInServerWords: Every refusal but 401 and 403 that carries the server's `msg`
	///     throws it as `.server`, instead of the meaning a 409 or 429 has for questions and
	///     the login limiter.
	static func send(
		_ method: String,
		_ path: String,
		baseURL: String,
		queryItems: [URLQueryItem] = [],
		percentEncodedQueryItems: [URLQueryItem] = [],
		headers: [(name: String, value: String)] = [],
		body: Data? = nil,
		refusalsInServerWords: Bool = false
	) async throws -> Data {
		try await sendForResponse(
			method,
			path,
			baseURL: baseURL,
			queryItems: queryItems,
			percentEncodedQueryItems: percentEncodedQueryItems,
			headers: headers,
			body: body,
			refusalsInServerWords: refusalsInServerWords
		).data
	}

	/// `send`, for a caller that reads the answer's headers too.
	static func sendForResponse(
		_ method: String,
		_ path: String,
		baseURL: String,
		queryItems: [URLQueryItem] = [],
		percentEncodedQueryItems: [URLQueryItem] = [],
		headers: [(name: String, value: String)] = [],
		body: Data? = nil,
		refusalsInServerWords: Bool = false
	) async throws -> (data: Data, response: HTTPURLResponse) {
		let request = try makeRequest(
			method,
			path,
			baseURL: baseURL,
			queryItems: queryItems,
			percentEncodedQueryItems: percentEncodedQueryItems,
			headers: headers,
			body: body
		)
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session(for: baseURL).data(for: request)
		}
		catch {
			throw HomerAPIError.unreachable(error.localizedDescription)
		}

		guard let http = response as? HTTPURLResponse else {
			throw HomerAPIError.unexpectedResponse
		}
		jar.update(for: baseURL, from: http)
		try check(http, body: data, refusalsInServerWords: refusalsInServerWords)
		return (data, http)
	}

	/// A server-sent event stream (`text/event-stream`), parsed into its events. It ends when
	/// the server closes it; cancelling the consuming task closes it from this side. Comments
	/// (the server's heartbeat pings) are skipped.
	static func events(
		_ path: String,
		baseURL: String,
		queryItems: [URLQueryItem] = [],
		headers: [(name: String, value: String)] = []
	) -> AsyncThrowingStream<HomerServerSentEvent, any Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					var request = try makeRequest(
						"GET",
						path,
						baseURL: baseURL,
						queryItems: queryItems,
						headers: headers,
						body: nil
					)
					request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
					let bytes: URLSession.AsyncBytes
					let response: URLResponse
					do {
						(bytes, response) = try await session(for: baseURL).bytes(for: request)
					}
					catch {
						throw HomerAPIError.unreachable(error.localizedDescription)
					}
					guard let http = response as? HTTPURLResponse else {
						throw HomerAPIError.unexpectedResponse
					}
					jar.update(for: baseURL, from: http)
					try check(http, body: Data(), refusalsInServerWords: false)

					var parser = HomerServerSentEventParser()
					var line: [UInt8] = []
					for try await byte in bytes {
						guard byte == UInt8(ascii: "\n") else {
							line.append(byte)
							continue
						}
						if let event = parser.consume(line: String(decoding: line, as: UTF8.self)) {
							continuation.yield(event)
						}
						line.removeAll(keepingCapacity: true)
					}
					continuation.finish()
				}
				catch is CancellationError {
					continuation.finish()
				}
				catch let error as HomerAPIError {
					continuation.finish(throwing: error)
				}
				catch {
					continuation.finish(throwing: HomerAPIError.unreachable(error.localizedDescription))
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	private static func makeRequest(
		_ method: String,
		_ path: String,
		baseURL: String,
		queryItems: [URLQueryItem],
		percentEncodedQueryItems: [URLQueryItem] = [],
		headers: [(name: String, value: String)],
		body: Data?
	) throws -> URLRequest {
		guard var components = URLComponents(string: baseURL + path) else {
			throw HomerAPIError.unexpectedResponse
		}
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}
		if !percentEncodedQueryItems.isEmpty {
			components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? []) + percentEncodedQueryItems
		}
		guard let url = components.url else {
			throw HomerAPIError.unexpectedResponse
		}

		var request = URLRequest(url: url, timeoutInterval: timeout)
		request.httpMethod = method
		request.httpBody = body
		for header in headers {
			request.setValue(header.value, forHTTPHeaderField: header.name)
		}
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		request.setValue("1", forHTTPHeaderField: csrfHeader)
		if body != nil {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		for (field, value) in HTTPCookie.requestHeaderFields(with: jar.cookies(for: baseURL)) {
			request.setValue(value, forHTTPHeaderField: field)
		}
		return request
	}

	private static func check(_ http: HTTPURLResponse, body data: Data, refusalsInServerWords: Bool) throws {
		switch http.statusCode {
		case 200 ..< 300:
			return
		case 401:
			throw HomerAPIError.unauthorized
		case 403:
			throw HomerAPIError.forbidden
		case _ where refusalsInServerWords && errorMessage(in: data) != nil:
			throw HomerAPIError.server(status: http.statusCode, message: errorMessage(in: data))
		case 409:
			throw HomerAPIError.conflict
		case 429:
			throw HomerAPIError.rateLimited
		default:
			throw HomerAPIError.server(status: http.statusCode, message: errorMessage(in: data))
		}
	}

	static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
		do {
			return try JSONDecoder().decode(type, from: data)
		}
		catch {
			// A 200 that is not the API's JSON is a base URL pointing at some other web page —
			// the console's own HTML, for one, answers every unknown path with 200.
			throw HomerAPIError.unexpectedResponse
		}
	}

	/// The `msg` of the backend's `{ "err": 1, "msg": "…" }` error body.
	private static func errorMessage(in data: Data) -> String? {
		struct ErrorBody: Decodable {
			var msg: String?
		}
		return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.msg
	}
}

/// One event of a `text/event-stream`.
nonisolated struct HomerServerSentEvent: Equatable, Sendable {
	var name: String
	var id: String?
	var data: String
}

/// The `text/event-stream` format, a line at a time: `event:`, `id:` and `data:` fields
/// accumulate until a blank line ends the event.
nonisolated struct HomerServerSentEventParser {
	private var name: String?
	private var id: String?
	private var dataLines: [String] = []

	mutating func consume(line rawLine: String) -> HomerServerSentEvent? {
		let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
		guard !line.isEmpty else {
			defer {
				name = nil
				id = nil
				dataLines = []
			}
			guard name != nil || !dataLines.isEmpty else {
				return nil
			}
			return HomerServerSentEvent(name: name ?? "message", id: id, data: dataLines.joined(separator: "\n"))
		}
		guard !line.hasPrefix(":") else {
			return nil
		}
		let field: Substring
		var value: Substring
		if let colon = line.firstIndex(of: ":") {
			field = line[..<colon]
			value = line[line.index(after: colon)...]
			if value.hasPrefix(" ") {
				value = value.dropFirst()
			}
		}
		else {
			field = Substring(line)
			value = ""
		}
		switch field {
		case "event":
			name = String(value)
		case "id":
			id = String(value)
		case "data":
			dataLines.append(String(value))
		default:
			break
		}
		return nil
	}
}
