import Foundation

// Mirrors of the Homer API's JSON (`console/types/homer.ts` in the Homer repo). Only the fields
// the native lists show are decoded; anything else the server sends is ignored, so a newer
// server keeps decoding. Timestamps are Unix epoch seconds throughout.

/// A process's lifecycle state. Unknown values (a newer server) decode as `.unknown` rather than
/// failing the whole list.
public nonisolated enum HomerProcessStatus: String, CaseIterable, Sendable, Hashable, Decodable {
	case created = "CREATED"
	case working = "WORKING"
	case finished = "FINISHED"
	case failed = "FAILED"
	case killed = "KILLED"
	case unknown = "UNKNOWN"

	/// The statuses the server accepts in the list's `types` filter, in the console's order.
	public static let filterable: [Self] = [.working, .finished, .failed, .killed, .created]

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}

	public var title: String {
		rawValue.capitalized
	}
}

public nonisolated struct HomerProcess: Equatable, Sendable, Identifiable, Decodable {
	public nonisolated struct HistoryEntry: Equatable, Sendable, Decodable {
		public var timestamp: Double
		public var status: HomerProcessStatus

		public init(timestamp: Double, status: HomerProcessStatus) {
			self.timestamp = timestamp
			self.status = status
		}
	}

	/// A finished command of the run (`ProcessExecution`).
	public nonisolated struct Execution: Equatable, Sendable, Decodable {
		public var label: String
		public var resultCode: Int
		public var skipped: Bool?
		public var start: Double?
		public var end: Double?
		/// The command's output files, as the server's absolute paths — `HomerArtifactPath`
		/// turns them into what the artifact calls take.
		public var stdOut: String?
		public var stdErr: String?
		/// Why the command failed, or why it was skipped.
		public var errMsg: String?

		public init(
			label: String,
			resultCode: Int,
			skipped: Bool? = nil,
			start: Double? = nil,
			end: Double? = nil,
			stdOut: String? = nil,
			stdErr: String? = nil,
			errMsg: String? = nil
		) {
			self.label = label
			self.resultCode = resultCode
			self.skipped = skipped
			self.start = start
			self.end = end
			self.stdOut = stdOut
			self.stdErr = stdErr
			self.errMsg = errMsg
		}
	}

	/// Where the run executes (`RunnerState`). The pod fields are set only for a Kubernetes
	/// runner.
	public nonisolated struct Runner: Equatable, Sendable, Decodable {
		/// Why the run's pod never became ready (`PodStartupFailure`).
		public nonisolated struct StartupFailure: Equatable, Sendable, Decodable {
			public var reason: String
			public var message: String
			public var events: [String]

			public init(reason: String, message: String, events: [String] = []) {
				self.reason = reason
				self.message = message
				self.events = events
			}

			public init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				reason = try container.decode(String.self, forKey: .reason)
				message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
				events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
			}

			private enum CodingKeys: String, CodingKey {
				case reason, message, events
			}
		}

		/// The backend's own name for the runner. Sent to admins only — everyone else gets the
		/// generic `type` (Homer ADR-0077).
		public var alias: String?
		/// `local`, `ssh`, `kubernetes`, `external` or `unknown`. Missing from servers older than
		/// ADR-0077, which always sent the alias.
		public var type: String?
		public var podName: String?
		public var podPhase: String?
		public var createdAt: Double?
		public var readyAt: Double?
		public var endedAt: Double?
		public var startupFailure: StartupFailure?

		public init(
			alias: String? = nil,
			type: String? = nil,
			podName: String? = nil,
			podPhase: String? = nil,
			createdAt: Double? = nil,
			readyAt: Double? = nil,
			endedAt: Double? = nil,
			startupFailure: StartupFailure? = nil
		) {
			self.alias = alias
			self.type = type
			self.podName = podName
			self.podPhase = podPhase
			self.createdAt = createdAt
			self.readyAt = readyAt
			self.endedAt = endedAt
			self.startupFailure = startupFailure
		}

		/// What the console's Runner column shows.
		public var displayName: String {
			alias ?? type ?? "-"
		}
	}

	public var id: Int
	public var status: HomerProcessStatus
	public var agentName: String
	/// Who started the run, e.g. `session:admin` or a bearer token's name.
	public var owner: String?
	public var history: [HistoryEntry]
	public var executions: [Execution]
	public var currentCommand: String?
	/// When the running command started, in epoch seconds.
	public var currentCommandStart: Double?
	/// When the run's workspace is deleted, in epoch seconds; nil while it runs or before the
	/// purge is scheduled.
	public var purgeAt: Double?
	public var runner: Runner?
	public var openQuestions: Int?
	/// Billed Claude spend for the run, from the server's cost ledger.
	public var costUsd: Double?
	/// The run that started this one; nil at a flow's root.
	public var parentProcessId: Int?
	/// The first run of this run's flow; nil at the root itself.
	public var rootProcessId: Int?
	public var tags: [String]?
	/// The run's Langfuse trace; nil unless the server has Langfuse configured.
	public var langfuseTraceUrl: String?

	public init(
		id: Int,
		status: HomerProcessStatus,
		agentName: String,
		owner: String? = nil,
		history: [HistoryEntry] = [],
		executions: [Execution] = [],
		currentCommand: String? = nil,
		currentCommandStart: Double? = nil,
		purgeAt: Double? = nil,
		runner: Runner? = nil,
		openQuestions: Int? = nil,
		costUsd: Double? = nil,
		parentProcessId: Int? = nil,
		rootProcessId: Int? = nil,
		tags: [String]? = nil,
		langfuseTraceUrl: String? = nil
	) {
		self.id = id
		self.status = status
		self.agentName = agentName
		self.owner = owner
		self.history = history
		self.executions = executions
		self.currentCommand = currentCommand
		self.currentCommandStart = currentCommandStart
		self.purgeAt = purgeAt
		self.runner = runner
		self.openQuestions = openQuestions
		self.costUsd = costUsd
		self.parentProcessId = parentProcessId
		self.rootProcessId = rootProcessId
		self.tags = tags
		self.langfuseTraceUrl = langfuseTraceUrl
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		id = try container.decode(Int.self, forKey: .id)
		status = try container.decode(HomerProcessStatus.self, forKey: .status)
		agentName = try container.decode(String.self, forKey: .agentName)
		owner = try container.decodeIfPresent(String.self, forKey: .owner)
		// Both are always sent today, but an absent array means "none", not a broken process.
		history = try container.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
		executions = try container.decodeIfPresent([Execution].self, forKey: .executions) ?? []
		currentCommand = try container.decodeIfPresent(String.self, forKey: .currentCommand)
		currentCommandStart = try container.decodeIfPresent(Double.self, forKey: .currentCommandStart)
		purgeAt = try container.decodeIfPresent(Double.self, forKey: .purgeAt)
		runner = try container.decodeIfPresent(Runner.self, forKey: .runner)
		openQuestions = try container.decodeIfPresent(Int.self, forKey: .openQuestions)
		costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
		parentProcessId = try container.decodeIfPresent(Int.self, forKey: .parentProcessId)
		rootProcessId = try container.decodeIfPresent(Int.self, forKey: .rootProcessId)
		tags = try container.decodeIfPresent([String].self, forKey: .tags)
		langfuseTraceUrl = try container.decodeIfPresent(String.self, forKey: .langfuseTraceUrl)
	}

	private enum CodingKeys: String, CodingKey {
		case id, status, agentName, owner, history, executions, currentCommand, currentCommandStart
		case purgeAt, runner, openQuestions, costUsd, parentProcessId, rootProcessId, tags
		case langfuseTraceUrl
	}

	/// A run that can still be killed (the console's `canKill`).
	public var isKillable: Bool {
		status == .working || status == .created
	}

	/// A run that has ended and can be started again with the same inputs (`canRetry`).
	public var isRetryable: Bool {
		status == .finished || status == .failed || status == .killed
	}

	/// A run the console offers to resume from its LangGraph checkpoint — if it has one, which
	/// only the LangGraph probe tells (`resumeEligible` on the process page).
	public var isResumeEligible: Bool {
		status == .failed || status == .killed || status == .unknown
	}

	/// When the process entered its current status: its last history entry, as the console's
	/// "Status Time" column shows it.
	public var statusDate: Date? {
		history.last.map { Date(timeIntervalSince1970: $0.timestamp) }
	}

	public enum LastCommandOutcome: Equatable, Sendable {
		case running
		case succeeded
		case failed
		case skipped
	}

	/// The console's "Last Command" column (`getLastCommand` in `lib/utils/process.ts`): the
	/// running command of a working process, else the most recent execution's outcome.
	public var lastCommand: (outcome: LastCommandOutcome, label: String)? {
		if status == .working, let currentCommand {
			return (.running, currentCommand)
		}
		guard let last = executions.last else {
			return nil
		}
		let outcome: LastCommandOutcome =
			if last.skipped == true {
				.skipped
			}
			else if last.resultCode == 0 {
				.succeeded
			}
			else {
				.failed
			}
		return (outcome, last.label)
	}
}

/// One page of `GET /api/v1/status/all`.
public nonisolated struct HomerProcessPage: Equatable, Sendable, Decodable {
	public var processes: [HomerProcess]
	public var total: Int

	public init(processes: [HomerProcess], total: Int) {
		self.processes = processes
		self.total = total
	}
}

/// Which runs the process list asks for — the web console's filters (`useProcesses`).
public nonisolated struct HomerProcessQuery: Equatable, Sendable {
	public var statuses: Set<HomerProcessStatus>
	/// Only the first run of each flow (the console's "Root runs" view).
	public var rootsOnly: Bool
	public var agentName: String?
	/// Runs carrying every one of these subject tags.
	public var tags: [String]
	/// The direct children of one run.
	public var parentProcessId: Int?
	/// Every run of one flow below its root — what a Flow cell summarizes.
	public var rootProcessId: Int?
	public var oldestFirst: Bool
	public var limit: Int

	public init(
		statuses: Set<HomerProcessStatus> = [],
		rootsOnly: Bool = false,
		agentName: String? = nil,
		tags: [String] = [],
		parentProcessId: Int? = nil,
		rootProcessId: Int? = nil,
		oldestFirst: Bool = false,
		limit: Int
	) {
		self.statuses = statuses
		self.rootsOnly = rootsOnly
		self.agentName = agentName
		self.tags = tags
		self.parentProcessId = parentProcessId
		self.rootProcessId = rootProcessId
		self.oldestFirst = oldestFirst
		self.limit = limit
	}

	/// Query items in the order the console sends them, from offset 0. A refresh always re-reads
	/// from the top, so pages loaded with "Load more" stay fresh too.
	var queryItems: [URLQueryItem] {
		var items: [URLQueryItem] = []
		let types = HomerProcessStatus.filterable.filter(statuses.contains).map(\.rawValue)
		if !types.isEmpty {
			items.append(URLQueryItem(name: "types", value: types.joined(separator: ",")))
		}
		if let agentName {
			items.append(URLQueryItem(name: "agentName", value: agentName))
		}
		if let parentProcessId {
			items.append(URLQueryItem(name: "parentProcessId", value: String(parentProcessId)))
		}
		if let rootProcessId {
			items.append(URLQueryItem(name: "rootProcessId", value: String(rootProcessId)))
		}
		if rootsOnly {
			items.append(URLQueryItem(name: "roots", value: "true"))
		}
		items += tags.map { URLQueryItem(name: "tag", value: $0) }
		items.append(URLQueryItem(name: "order", value: oldestFirst ? "asc" : "desc"))
		items.append(URLQueryItem(name: "limit", value: String(limit)))
		items.append(URLQueryItem(name: "offset", value: "0"))
		return items
	}
}

/// The Flow cell of a root run (`flow-summary-cell.tsx`): the runs under it, what they cost
/// together and their aggregate state. The root's own status and cost are in its row already.
public nonisolated struct HomerFlowSummary: Equatable, Sendable {
	/// Aggregate state, most actionable first.
	public enum State: Equatable, Sendable {
		case question
		case running
		case failed
		case finished
	}

	/// Runs fetched per root. The count comes from the page's `total`, so the cap bounds only
	/// the cost sum and the state.
	public static let fetchLimit = 100

	public var runCount: Int
	public var costUsd: Double
	public var state: State?
	/// More runs than were fetched: cost and state cover the newest `fetchLimit` only.
	public var isPartial: Bool

	public init(runCount: Int, costUsd: Double, state: State?, isPartial: Bool) {
		self.runCount = runCount
		self.costUsd = costUsd
		self.state = state
		self.isPartial = isPartial
	}

	/// The question check comes first: a question exists only while its run is working, so
	/// ranking `running` above it would make that state unreachable. Killed reads as failed.
	public init(page: HomerProcessPage) {
		let runs = page.processes
		self.runCount = page.total
		self.costUsd = runs.reduce(0) { $0 + ($1.costUsd ?? 0) }
		self.isPartial = page.total > runs.count
		self.state =
			if runs.isEmpty {
				nil
			}
			else if runs.contains(where: { ($0.openQuestions ?? 0) > 0 }) {
				.question
			}
			else if runs.contains(where: { $0.status == .working || $0.status == .created }) {
				.running
			}
			else if runs.contains(where: { $0.status == .failed || $0.status == .killed }) {
				.failed
			}
			else {
				.finished
			}
	}
}

public nonisolated enum HomerQuestionStatus: String, Sendable, Hashable, Decodable {
	case open = "OPEN"
	case answered = "ANSWERED"
	case expired = "EXPIRED"
	case unknown

	public init(from decoder: any Decoder) throws {
		let raw = try decoder.singleValueContainer().decode(String.self)
		self = Self(rawValue: raw.uppercased()) ?? .unknown
	}
}

/// A human-in-the-loop question a running command asked (`GET /api/v1/questions`).
public nonisolated struct HomerQuestion: Equatable, Sendable, Identifiable, Decodable {
	/// Present when answering the question starts another agent (ask-and-dispatch).
	public nonisolated struct Dispatch: Equatable, Sendable, Decodable {
		public var agentName: String
		public var status: String
		public var dispatchedProcessId: Int?
		public var error: String?

		public init(agentName: String, status: String, dispatchedProcessId: Int? = nil, error: String? = nil) {
			self.agentName = agentName
			self.status = status
			self.dispatchedProcessId = dispatchedProcessId
			self.error = error
		}
	}

	public var id: String
	public var processId: Int
	public var agentName: String
	/// Markdown written by the agent.
	public var text: String
	/// Predefined answers, offered as buttons. May be empty: then only a free-text answer fits.
	public var options: [String]
	public var status: HomerQuestionStatus
	public var answer: String?
	public var createdAt: Double
	public var dispatch: Dispatch?

	public init(
		id: String,
		processId: Int,
		agentName: String,
		text: String,
		options: [String] = [],
		status: HomerQuestionStatus = .open,
		answer: String? = nil,
		createdAt: Double,
		dispatch: Dispatch? = nil
	) {
		self.id = id
		self.processId = processId
		self.agentName = agentName
		self.text = text
		self.options = options
		self.status = status
		self.answer = answer
		self.createdAt = createdAt
		self.dispatch = dispatch
	}

	public var createdDate: Date {
		Date(timeIntervalSince1970: createdAt)
	}
}

nonisolated struct HomerQuestionList: Decodable {
	var questions: [HomerQuestion]
}

/// The signed-in principal (`GET /api/v1/auth/me`).
public nonisolated struct HomerUser: Equatable, Sendable, Decodable {
	/// What the user may do on which agents. `agents` are names or prefix patterns ending in
	/// `*`; `actions` are `run`, `read`, `control`, `edit`, `debug`.
	public nonisolated struct Grant: Equatable, Sendable, Decodable {
		public var agents: [String]
		public var actions: [String]

		public init(agents: [String], actions: [String]) {
			self.agents = agents
			self.actions = actions
		}
	}

	public var username: String
	public var role: String?
	public var grants: [Grant]

	public init(username: String, role: String? = nil, grants: [Grant] = []) {
		self.username = username
		self.role = role
		self.grants = grants
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		username = try container.decode(String.self, forKey: .username)
		role = try container.decodeIfPresent(String.self, forKey: .role)
		grants = try container.decodeIfPresent([Grant].self, forKey: .grants) ?? []
	}

	private enum CodingKeys: String, CodingKey {
		case username, role, grants
	}

	public var isAdmin: Bool {
		role == "admin"
	}

	// The console's `capabilitiesFor` (`lib/auth/use-can.ts`): it only decides which buttons to
	// offer — the server checks every call again.

	public func canKill(_ process: HomerProcess) -> Bool {
		isAdmin || owns(process) || (canSee(process) && can("control", agent: process.agentName))
	}

	public func canRetry(_ process: HomerProcess) -> Bool {
		canSee(process) && can("run", agent: process.agentName)
	}

	private func canSee(_ process: HomerProcess) -> Bool {
		isAdmin || owns(process) || can("read", agent: process.agentName)
	}

	/// A console session's runs are owned by `session:<username>`.
	private func owns(_ process: HomerProcess) -> Bool {
		isAdmin || process.owner == "session:\(username)"
	}

	private func can(_ action: String, agent: String) -> Bool {
		isAdmin || grants.contains { grant in
			grant.actions.contains(action) && grant.agents.contains { Self.agentPattern($0, matches: agent) }
		}
	}

	/// Homer's `AgentNameMatcher`: `*` matches every agent, `prefix*` a prefix, else exact.
	static func agentPattern(_ pattern: String, matches name: String) -> Bool {
		if pattern == "*" {
			return true
		}
		if pattern.hasSuffix("*") {
			return name.hasPrefix(pattern.dropLast())
		}
		return pattern == name
	}
}

nonisolated struct HomerAgentList: Decodable {
	nonisolated struct Agent: Decodable {
		var name: String
	}

	var agents: [Agent]
}

nonisolated struct HomerRetryResponse: Decodable {
	var processId: Int
}
