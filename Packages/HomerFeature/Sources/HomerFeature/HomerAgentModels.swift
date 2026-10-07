import Foundation

// Mirrors of `GET /api/v1/agents` and the agent calls (`AgentInfo`, `AgentInput`,
// `AgentCronInfo`, `AgentReloadResult` in the console's `types/homer.ts`; `AgentInfo` and
// `Param` in the backend's `models/ServerStatus.kt` and `models/Agent.kt`). Decoded as leniently
// as the other models: a missing field takes the backend's default, unknown values are kept as
// they came. Timestamps are Unix epoch seconds.

/// An agent the signed-in user holds any grant on — the server lists no others.
public nonisolated struct HomerAgent: Equatable, Sendable, Identifiable, Decodable {
	/// A declared input: where the run reads it from on the request, and the environment
	/// variable the agent's commands see it as.
	public nonisolated struct Input: Equatable, Sendable, Identifiable, Decodable {
		/// Where `POST /api/v1/agent/{name}` reads the input from.
		public enum Source: String, Equatable, Sendable {
			case query
			case body
			case header
			/// A newer server's source: neither shown nor sent, as the console groups inputs by
			/// the three it knows.
			case unknown
		}

		/// How the server extracts the value from what was sent.
		public nonisolated struct Transformer: Equatable, Sendable, Decodable {
			/// `pass`, `jsonPath` or (older servers) `regex`.
			public var type: String
			public var path: String?
			public var pattern: String?
			public var group: Int?

			public static let pass = Transformer(type: "pass")

			public init(type: String, path: String? = nil, pattern: String? = nil, group: Int? = nil) {
				self.type = type
				self.path = path
				self.pattern = pattern
				self.group = group
			}

			public var isJSONPath: Bool {
				type == "jsonPath"
			}

			/// The console's `getTransformerDescription` (`lib/utils/agent.ts`).
			public var summary: String {
				switch type {
				case "pass":
					"Direct pass-through"
				case "jsonPath":
					"Extract JSON path: \(path ?? "unknown")"
				case "regex":
					"Regex match: \(pattern ?? "unknown")" + (group.map { " (group \($0))" } ?? "")
				default:
					"Unknown transformer"
				}
			}
		}

		public var paramName: String
		public var envName: String
		public var source: Source
		/// `STRING`, `NUMBER`, `ANY` (the legacy generation the console validates) or a typed
		/// one (`string`, `integer`, `number`, `boolean`), which only the server checks.
		public var type: String
		public var required: Bool
		public var transformer: Transformer

		public init(
			paramName: String,
			envName: String? = nil,
			source: Source = .query,
			type: String = "STRING",
			required: Bool = true,
			transformer: Transformer = .pass
		) {
			self.paramName = paramName
			self.envName = envName ?? paramName
			self.source = source
			self.type = type
			self.required = required
			self.transformer = transformer
		}

		/// Absent fields take the backend's `Param` defaults.
		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			paramName = try container.decode(String.self, forKey: .paramName)
			envName = try container.decodeIfPresent(String.self, forKey: .envName) ?? paramName
			source = try container.decodeIfPresent(String.self, forKey: .src)
				.map { Source(rawValue: $0.lowercased()) ?? .unknown } ?? .query
			type = try container.decodeIfPresent(String.self, forKey: .type) ?? "STRING"
			required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? true
			transformer = try container.decodeIfPresent(Transformer.self, forKey: .transformer) ?? .pass
		}

		private enum CodingKeys: String, CodingKey {
			case paramName, envName, src, type, required, transformer
		}

		public var id: String {
			paramName
		}
	}

	/// The agent's schedule, with what the server's scheduler knows of it.
	public nonisolated struct Cron: Equatable, Sendable, Decodable {
		public var expression: String
		public var timezone: String
		public var nextRunAt: Double?
		public var lastRunAt: Double?
		/// The run the last firing started, if it started one.
		public var lastRunProcessId: Int?

		public init(
			expression: String,
			timezone: String,
			nextRunAt: Double? = nil,
			lastRunAt: Double? = nil,
			lastRunProcessId: Int? = nil
		) {
			self.expression = expression
			self.timezone = timezone
			self.nextRunAt = nextRunAt
			self.lastRunAt = lastRunAt
			self.lastRunProcessId = lastRunProcessId
		}

		public init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			expression = try container.decode(String.self, forKey: .expression)
			timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? ""
			nextRunAt = try container.decodeIfPresent(Double.self, forKey: .nextRunAt)
			lastRunAt = try container.decodeIfPresent(Double.self, forKey: .lastRunAt)
			lastRunProcessId = try container.decodeIfPresent(Int.self, forKey: .lastRunProcessId)
		}

		private enum CodingKeys: String, CodingKey {
			case expression, timezone, nextRunAt, lastRunAt, lastRunProcessId
		}
	}

	public var name: String
	public var description: String?
	/// The declared inputs: `inputs`, else the deprecated `queryParams` alias (`getAgentInputs`).
	public var inputs: [Input]
	/// How many commands the agent runs (the card's "Scripts").
	public var scriptCount: Int
	public var cron: Cron?
	/// Whether its files can be edited — false for agents baked into the server's image.
	public var isWritable: Bool

	public init(
		name: String,
		description: String? = nil,
		inputs: [Input] = [],
		scriptCount: Int = 1,
		cron: Cron? = nil,
		isWritable: Bool = true
	) {
		self.name = name
		self.description = description
		self.inputs = inputs
		self.scriptCount = scriptCount
		self.cron = cron
		self.isWritable = isWritable
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		name = try container.decode(String.self, forKey: .name)
		description = try container.decodeIfPresent(String.self, forKey: .description)
		inputs = try container.decodeIfPresent([Input].self, forKey: .inputs)
			?? container.decodeIfPresent([Input].self, forKey: .queryParams)
			?? []
		scriptCount = try container.decodeIfPresent(Int.self, forKey: .scriptCount) ?? 0
		cron = try container.decodeIfPresent(Cron.self, forKey: .cron)
		// The console offers Edit only when the server says so (`agent.writable && …`).
		isWritable = try container.decodeIfPresent(Bool.self, forKey: .writable) ?? false
	}

	private enum CodingKeys: String, CodingKey {
		case name, description, inputs, queryParams, scriptCount, cron, writable
	}

	public var id: String {
		name
	}

	/// The agent's console route, e.g. `agents/factory` — the name encoded as the console's
	/// `encodeURIComponent` does.
	public var consolePath: String {
		"agents/" + Self.encodeURIComponent(name)
	}

	/// JavaScript's `encodeURIComponent`, for an agent name in a path.
	static func encodeURIComponent(_ string: String) -> String {
		string.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? string
	}

	/// `encodeURIComponent`'s unreserved characters.
	private static let uriComponentAllowed = CharacterSet(
		charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
	)

	/// The inputs the Run sheet shows and sends, grouped as the console groups them.
	public var queryInputs: [Input] {
		inputs.filter { $0.source == .query }
	}

	public var bodyInputs: [Input] {
		inputs.filter { $0.source == .body }
	}

	public var headerInputs: [Input] {
		inputs.filter { $0.source == .header }
	}

	/// The Schedules page (`schedules/page.tsx`): the agents with a cron, soonest next run first
	/// and those with none last. Ties keep the given order (the list's, by name).
	public static func schedules(_ agents: some Sequence<HomerAgent>) -> [HomerAgent] {
		agents.enumerated()
			.filter { $0.element.cron != nil }
			.sorted { lhs, rhs in
				let left = lhs.element.cron?.nextRunAt ?? .infinity
				let right = rhs.element.cron?.nextRunAt ?? .infinity
				return left == right ? lhs.offset < rhs.offset : left < right
			}
			.map(\.element)
	}
}

nonisolated struct HomerAgentListResponse: Decodable {
	var agents: [HomerAgent]
}

/// What `POST /api/v1/agents/reload` changed.
public nonisolated struct HomerAgentReloadResult: Equatable, Sendable, Decodable {
	public var added: [String]
	public var updated: [String]
	public var removed: [String]
	/// Agents that failed to load, as the server words it.
	public var errors: [String]

	public init(added: [String] = [], updated: [String] = [], removed: [String] = [], errors: [String] = []) {
		self.added = added
		self.updated = updated
		self.removed = removed
		self.errors = errors
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		added = try container.decodeIfPresent([String].self, forKey: .added) ?? []
		updated = try container.decodeIfPresent([String].self, forKey: .updated) ?? []
		removed = try container.decodeIfPresent([String].self, forKey: .removed) ?? []
		errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case added, updated, removed, errors
	}

	public var hasChanges: Bool {
		!added.isEmpty || !updated.isEmpty || !removed.isEmpty
	}
}

/// The answer of `POST /api/v1/agent/{name}`: the run it started.
nonisolated struct HomerAgentRunResponse: Decodable {
	var processId: Int
}
