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

	public nonisolated struct Execution: Equatable, Sendable, Decodable {
		public var label: String
		public var resultCode: Int
		public var skipped: Bool?

		public init(label: String, resultCode: Int, skipped: Bool? = nil) {
			self.label = label
			self.resultCode = resultCode
			self.skipped = skipped
		}
	}

	public var id: Int
	public var status: HomerProcessStatus
	public var agentName: String
	public var owner: String?
	public var history: [HistoryEntry]
	public var executions: [Execution]
	public var currentCommand: String?
	public var openQuestions: Int?
	public var costUsd: Double?
	public var parentProcessId: Int?
	public var tags: [String]?

	public init(
		id: Int,
		status: HomerProcessStatus,
		agentName: String,
		owner: String? = nil,
		history: [HistoryEntry] = [],
		executions: [Execution] = [],
		currentCommand: String? = nil,
		openQuestions: Int? = nil,
		costUsd: Double? = nil,
		parentProcessId: Int? = nil,
		tags: [String]? = nil
	) {
		self.id = id
		self.status = status
		self.agentName = agentName
		self.owner = owner
		self.history = history
		self.executions = executions
		self.currentCommand = currentCommand
		self.openQuestions = openQuestions
		self.costUsd = costUsd
		self.parentProcessId = parentProcessId
		self.tags = tags
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
		openQuestions = try container.decodeIfPresent(Int.self, forKey: .openQuestions)
		costUsd = try container.decodeIfPresent(Double.self, forKey: .costUsd)
		parentProcessId = try container.decodeIfPresent(Int.self, forKey: .parentProcessId)
		tags = try container.decodeIfPresent([String].self, forKey: .tags)
	}

	private enum CodingKeys: String, CodingKey {
		case id, status, agentName, owner, history, executions, currentCommand, openQuestions, costUsd
		case parentProcessId, tags
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

/// Which runs the process list asks for. `roots` hides the runs other runs started.
public nonisolated struct HomerProcessQuery: Equatable, Sendable {
	public var statuses: Set<HomerProcessStatus>
	public var rootsOnly: Bool
	public var limit: Int

	public init(statuses: Set<HomerProcessStatus> = [], rootsOnly: Bool = false, limit: Int) {
		self.statuses = statuses
		self.rootsOnly = rootsOnly
		self.limit = limit
	}

	/// Query items in the order the console sends them, newest first from offset 0. A refresh
	/// always re-reads from the top, so pages loaded with "Load more" stay fresh too.
	var queryItems: [URLQueryItem] {
		var items: [URLQueryItem] = []
		let types = HomerProcessStatus.filterable.filter(statuses.contains).map(\.rawValue)
		if !types.isEmpty {
			items.append(URLQueryItem(name: "types", value: types.joined(separator: ",")))
		}
		if rootsOnly {
			items.append(URLQueryItem(name: "roots", value: "true"))
		}
		items.append(URLQueryItem(name: "order", value: "desc"))
		items.append(URLQueryItem(name: "limit", value: String(limit)))
		items.append(URLQueryItem(name: "offset", value: "0"))
		return items
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
	public var username: String
	public var role: String?

	public init(username: String, role: String? = nil) {
		self.username = username
		self.role = role
	}
}
