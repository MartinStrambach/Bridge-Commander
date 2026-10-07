import Foundation

/// What the Run sheet sends to `POST /api/v1/agent/{name}`: each input by its source (the
/// console's `buildExecuteOpts` and `homerApi.executeAgent`).
///
/// Unlike the console, an empty value is never sent, from any source — the console skips only
/// empty query values and sends `""` for an empty body or header input, which overrides the
/// input's declared `default` on the server and fails a typed input's validation.
public nonisolated struct HomerAgentRunRequest: Equatable, Sendable {
	public nonisolated struct Field: Equatable, Sendable {
		public var name: String
		public var value: String

		public init(_ name: String, _ value: String) {
			self.name = name
			self.value = value
		}
	}

	public var queryItems: [URLQueryItem]
	/// A JSON object of string values; nil when the agent reads nothing from the body. An agent
	/// with body inputs is always sent one, `{}` if every value is empty: the server insists on
	/// a JSON body whenever an input comes from it.
	public var bodyFields: [Field]?
	public var headers: [Field]

	public init(
		queryItems: [URLQueryItem] = [],
		bodyFields: [Field]? = nil,
		headers: [Field] = []
	) {
		self.queryItems = queryItems
		self.bodyFields = bodyFields
		self.headers = headers
	}

	public init(agent: HomerAgent, values: [String: String]) {
		func filled(_ inputs: [HomerAgent.Input]) -> [Field] {
			inputs.compactMap { input in
				let value = values[input.paramName] ?? ""
				return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Field(input.paramName, value)
			}
		}
		self.queryItems = filled(agent.queryInputs).map { URLQueryItem(name: $0.name, value: $0.value) }
		self.bodyFields = agent.bodyInputs.isEmpty ? nil : filled(agent.bodyInputs)
		self.headers = filled(agent.headerInputs)
	}

	/// The body as JSON, its fields in the inputs' order.
	public var bodyJSON: Data? {
		guard let bodyFields else {
			return nil
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = .withoutEscapingSlashes
		let members = bodyFields.map { field in
			Self.jsonString(field.name, encoder: encoder) + ":" + Self.jsonString(field.value, encoder: encoder)
		}
		return Data(("{" + members.joined(separator: ",") + "}").utf8)
	}

	private static func jsonString(_ string: String, encoder: JSONEncoder) -> String {
		(try? encoder.encode(string)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
	}

	/// The query items percent-encoded as `URLSearchParams` would be, `+` included: left to
	/// `URLComponents` a `+` goes out as is, and the server reads it as a space.
	var percentEncodedQueryItems: [URLQueryItem] {
		queryItems.map { item in
			URLQueryItem(
				name: HomerAgent.encodeURIComponent(item.name),
				value: item.value.map(HomerAgent.encodeURIComponent)
			)
		}
	}

	/// The agent's run endpoint, e.g. `/api/v1/agent/factory`.
	static func path(agentName: String) -> String {
		"/api/v1/agent/" + HomerAgent.encodeURIComponent(agentName)
	}

	/// The console's "Export Curl" tab (`lib/utils/curl.ts`), against the instance's own URL.
	/// Every argument is single-quoted, so no value is expanded by the shell. It carries no
	/// credentials, as the console's does not in cookie mode.
	public func curlCommand(baseURL: String, agentName: String) -> String {
		var components = URLComponents(string: baseURL + Self.path(agentName: agentName))
		if !queryItems.isEmpty {
			components?.percentEncodedQueryItems = percentEncodedQueryItems
		}
		let url = components?.string ?? baseURL + Self.path(agentName: agentName)
		var lines = ["curl -X POST \(Self.shellQuoted(url))"]
		lines += headers.map { "-H \(Self.shellQuoted("\($0.name): \($0.value)"))" }
		if let body = bodyJSON.flatMap({ String(data: $0, encoding: .utf8) }) {
			lines.append("-H 'Content-Type: application/json'")
			lines.append("-d \(Self.shellQuoted(body))")
		}
		return lines.joined(separator: " \\\n  ")
	}

	/// `'…'`, with each `'` written as `'\''`.
	static func shellQuoted(_ string: String) -> String {
		"'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}

/// The Run sheet's checks (the console's `lib/utils/validation.ts`). Typed inputs (`integer`,
/// `boolean`, …) get only the required check, as in the console; the server validates them.
public nonisolated enum HomerAgentInputValidation {
	/// Why `value` is not acceptable for `input`, or nil.
	public static func error(for input: HomerAgent.Input, value: String) -> String? {
		let isBlank = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		if isBlank {
			return input.required ? "This field is required" : nil
		}
		if input.transformer.isJSONPath {
			let isJSON = (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)) != nil
			return isJSON ? nil : "Must be valid JSON (JSONPath transformer requires JSON input)"
		}
		switch input.type {
		case "STRING":
			return value.contains(" ") ? "String values cannot contain spaces" : nil
		case "NUMBER":
			return isInteger(value) ? nil : "Must be a valid integer"
		default:
			return nil
		}
	}

	/// The errors of every input, keyed by parameter name.
	public static func errors(for inputs: [HomerAgent.Input], values: [String: String]) -> [String: String] {
		var errors: [String: String] = [:]
		for input in inputs {
			if let error = error(for: input, value: values[input.paramName] ?? "") {
				errors[input.paramName] = error
			}
		}
		return errors
	}

	/// `/^-?\d+$/`, ASCII digits only as in JavaScript.
	private static func isInteger(_ value: String) -> Bool {
		let digits = value.hasPrefix("-") ? value.dropFirst() : Substring(value)
		return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
	}
}
