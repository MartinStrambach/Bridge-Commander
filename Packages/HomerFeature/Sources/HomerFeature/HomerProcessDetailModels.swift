import Foundation

// The process page's part of the API (`console/types/homer.ts`): a run's LangGraph workflow
// status, its artifacts and the live tail of a command's output.

/// A run's LangGraph workflow (`LangGraphRunStatus`, `GET /api/v1/processes/{id}/langgraph`).
/// Without `?graph=true` only the identifying fields are sent — the probe that tells whether the
/// run has a workflow at all (404 when it has none) and which of its commands runs it.
public nonisolated struct HomerLangGraphStatus: Equatable, Sendable, Decodable {
	/// A sub-agent run a parked node dispatched (`LangGraphSubProgress`).
	public nonisolated struct Sub: Equatable, Sendable, Decodable {
		/// One command of the sub run: `ok`, `failed`, `skipped` or `running`.
		public nonisolated struct Command: Equatable, Sendable, Decodable {
			public var label: String
			public var state: String

			public init(label: String, state: String) {
				self.label = label
				self.state = state
			}
		}

		public var interruptId: String
		public var processId: Int?
		public var agentName: String?
		/// The sub run's process status; nil once the run left the process store.
		public var status: String?
		public var commands: [Command]?

		public init(
			interruptId: String,
			processId: Int? = nil,
			agentName: String? = nil,
			status: String? = nil,
			commands: [Command]? = nil
		) {
			self.interruptId = interruptId
			self.processId = processId
			self.agentName = agentName
			self.status = status
			self.commands = commands
		}
	}

	/// A node and its state, in graph order.
	public nonisolated struct Node: Equatable, Sendable {
		public var name: String
		/// `done`, `failed`, `parked` or `pending`; anything else is shown as sent.
		public var state: String

		public init(name: String, state: String) {
			self.name = name
			self.state = state
		}
	}

	/// The command whose run is the workflow — the execution the status belongs to.
	public var label: String
	public var module: String?
	public var threadId: String
	public var mermaid: String?
	/// Each node's state, by name. JSON objects carry no order a `Dictionary` keeps; `nodes`
	/// puts them in graph order.
	public var nodeStates: [String: String]?
	public var errors: [String: String]?
	public var subs: [String: [Sub]]?
	/// Nodes whose interrupt history hit the runtime's cap: their oldest subs are missing.
	public var subsTruncated: [String]?
	/// Why the status could not be read. The other fields are then unreliable.
	public var error: String?

	public init(
		label: String,
		module: String? = nil,
		threadId: String,
		mermaid: String? = nil,
		nodeStates: [String: String]? = nil,
		errors: [String: String]? = nil,
		subs: [String: [Sub]]? = nil,
		subsTruncated: [String]? = nil,
		error: String? = nil
	) {
		self.label = label
		self.module = module
		self.threadId = threadId
		self.mermaid = mermaid
		self.nodeStates = nodeStates
		self.errors = errors
		self.subs = subs
		self.subsTruncated = subsTruncated
		self.error = error
	}

	private enum CodingKeys: String, CodingKey {
		case label, module, threadId, mermaid, errors, subs, subsTruncated, error
		case nodeStates = "nodes"
	}

	/// The nodes in the order the Mermaid source declares them — LangGraph's `draw_mermaid`
	/// writes them in the order the graph added them, which is the workflow's own reading
	/// order. Nodes it does not declare (or every node, with no source) follow by name.
	public var nodes: [Node] {
		guard let nodeStates else {
			return []
		}
		let order = mermaid.map(Self.declaredNodeIDs(in:)) ?? [:]
		return nodeStates
			.map { Node(name: $0.key, state: $0.value) }
			.sorted { lhs, rhs in
				let left = order[Self.mermaidSafeID(lhs.name)] ?? .max
				let right = order[Self.mermaidSafeID(rhs.name)] ?? .max
				return left != right ? left < right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
			}
	}

	/// Every sub run, node by node in graph order.
	public var allSubs: [(node: String, sub: Sub)] {
		nodes.flatMap { node in (subs?[node.name] ?? []).map { (node.name, $0) } }
	}

	/// A parked node whose sub runs have all finished: its agents' work is done, but the join
	/// has not resolved, so the node itself has not completed (`lgSubDone` in the console).
	public func subsFinished(node: String) -> Bool {
		guard nodeStates?[node] == "parked", let nodeSubs = subs?[node], !nodeSubs.isEmpty else {
			return false
		}
		return nodeSubs.allSatisfy { $0.status == "FINISHED" }
	}

	/// The node ids of a Mermaid flowchart's declaration lines (`\tplan(plan)`,
	/// `\t__start__([<p>__start__</p>]):::first`), by their position.
	static func declaredNodeIDs(in mermaid: String) -> [String: Int] {
		var order: [String: Int] = [:]
		for line in mermaid.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let open = trimmed.firstIndex(where: { $0 == "(" || $0 == "[" }), open != trimmed.startIndex else {
				continue
			}
			let id = String(trimmed[..<open])
			// Edges (`a --> b;`) hold spaces or arrows before any bracket.
			guard !id.contains(" "), !id.contains("-->"), order[id] == nil else {
				continue
			}
			order[id] = order.count
		}
		return order
	}

	/// The node id `draw_mermaid` writes for a node name (langchain_core's `_to_safe_id`):
	/// characters outside `[a-zA-Z0-9_-]` become a backslash and their lowercase hex code
	/// point.
	static func mermaidSafeID(_ name: String) -> String {
		var id = ""
		for scalar in name.unicodeScalars {
			if scalar.isASCII, scalar.properties.isAlphabetic || ("0" ... "9").contains(scalar) || scalar == "_" || scalar == "-" {
				id.unicodeScalars.append(scalar)
			}
			else {
				id += "\\" + String(scalar.value, radix: 16)
			}
		}
		return id
	}
}

/// A file in a run's artifacts directory (`GET /api/v1/artifacts/list`).
public nonisolated struct HomerArtifact: Equatable, Sendable, Identifiable, Decodable {
	/// Relative to the artifacts directory — what the artifact calls take.
	public var path: String
	public var size: Int
	/// Epoch seconds.
	public var modified: Double

	public init(path: String, size: Int, modified: Double) {
		self.path = path
		self.size = size
		self.modified = modified
	}

	public var id: String {
		path
	}
}

nonisolated struct HomerArtifactListing: Decodable {
	var files: [HomerArtifact]
}

/// An artifact's content as `GET /api/v1/artifacts` serves it.
public nonisolated struct HomerArtifactContent: Equatable, Sendable {
	public var text: String
	/// The file's length in bytes when it was read — where the live tail resumes.
	public var byteCount: Int
	/// `X-File-Complete`: false while the command is still writing the file.
	public var isComplete: Bool

	public init(text: String, byteCount: Int, isComplete: Bool) {
		self.text = text
		self.byteCount = byteCount
		self.isComplete = isComplete
	}
}

/// What the live tail of a command's output (`GET /api/v1/stream/processes/{id}/logs`) sends.
public nonisolated enum HomerLogEvent: Equatable, Sendable {
	/// New bytes, and the file's length after them (the SSE event's id).
	case chunk(text: String, endOffset: Int)
	/// The process ended and the last bytes were sent.
	case end
}

/// A command's output on the server: `stdout` is `cmd_N.out`, `stderr` `cmd_N.err`.
public nonisolated enum HomerOutputStream: String, CaseIterable, Equatable, Sendable {
	case stdout
	case stderr

	/// The log stream's `stream` parameter.
	var apiValue: String {
		self == .stdout ? "out" : "err"
	}

	public var title: String {
		self == .stdout ? "Stdout" : "Stderr"
	}
}

public nonisolated enum HomerArtifactPath {
	/// The `path` the artifact calls take (`toArtifactApiPath`): an execution's absolute
	/// `stdOut`/`stdErr` is cut to its file name — command output lies flat in the artifacts
	/// directory — and a relative path (from the artifact list) stays as it is, sub-directory
	/// and all.
	public static func apiPath(_ path: String) -> String {
		path.hasPrefix("/") ? fileName(path) : path
	}

	public static func fileName(_ path: String) -> String {
		path.split(separator: "/").last.map(String.init) ?? "artifact"
	}

	/// The running command's output files, which no execution names yet.
	public static func liveOutput(executionIndex: Int, stream: HomerOutputStream) -> String {
		"cmd_\(executionIndex).\(stream == .stdout ? "out" : "err")"
	}
}
