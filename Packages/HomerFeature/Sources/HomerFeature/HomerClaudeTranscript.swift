import Foundation

/// A Claude command's stdout read as a conversation (`claude-artifact-view.tsx`): Claude CLI's
/// `--output-format stream-json` writes one JSON event per line (`cmd_N.out` is NDJSON), and the
/// console shows them as Claude's messages and tool calls rather than as raw JSON.
///
/// Built incrementally, so the live tail adds only its new lines: `append` keeps a trailing line
/// without its newline until the rest of it arrives.
public nonisolated struct HomerClaudeTranscript: Equatable, Sendable {
	/// The run's `result` event: what the finished conversation cost and took.
	public nonisolated struct Outcome: Equatable, Sendable {
		public var isError: Bool
		public var costUsd: Double
		public var inputTokens: Int
		public var outputTokens: Int
		public var cacheReadTokens: Int
		public var cacheCreationTokens: Int
		public var durationMs: Double
		public var apiDurationMs: Double
		public var turns: Int
	}

	public nonisolated enum Item: Equatable, Sendable, Identifiable {
		case message(id: String, text: String)
		case tool(Tool)

		public var id: String {
			switch self {
			case let .message(id, _):
				id
			case let .tool(tool):
				"tool-" + tool.id
			}
		}
	}

	public nonisolated struct Tool: Equatable, Sendable {
		public var id: String
		public var name: String
		/// The call's input as indented JSON.
		public var input: String
		/// The input on one line, cut short — the collapsed row's hint.
		public var inputPreview: String
		/// The tool's answer; nil while the call is in flight.
		public var result: String?
	}

	/// The model, from the `system` init event. Its presence is what makes the output a Claude
	/// conversation: hook events are `system` too and may come first, but carry no model.
	public private(set) var model: String?
	public private(set) var outcome: Outcome?
	public private(set) var items: [Item] = []
	/// Distinct assistant messages so far. Claude streams one message as several `assistant`
	/// events sharing its id, so counting events would overshoot the result's `num_turns`.
	public var turns: Int {
		messageIDs.count
	}

	/// The latest assistant message's usage — the live header's running token count.
	public private(set) var runningUsage: (input: Int, output: Int)?

	private var messageIDs: Set<String> = []
	private var toolIndices: [String: Int] = [:]
	private var pendingLine = ""

	public init() {}

	public init(parsing text: String) {
		append(text)
	}

	public var isClaude: Bool {
		model != nil
	}

	/// The most recent tool call without a result, which a live view marks as running.
	public var inflightToolID: String? {
		for item in items.reversed() {
			if case let .tool(tool) = item, tool.result == nil {
				return tool.id
			}
		}
		return nil
	}

	/// Index of the last message: shown in full, every earlier one collapsed.
	public var lastMessageIndex: Int? {
		items.lastIndex { if case .message = $0 { true } else { false } }
	}

	public mutating func append(_ text: String) {
		var lines = (pendingLine + text).split(separator: "\n", omittingEmptySubsequences: false)
		pendingLine = String(lines.removeLast())
		for line in lines {
			consume(line)
		}
		// A complete event without its newline yet — the end of a finished file, typically.
		// It is applied now and kept as pending only if it does not parse.
		if !pendingLine.isEmpty, consume(Substring(pendingLine)) {
			pendingLine = ""
		}
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.model == rhs.model && lhs.outcome == rhs.outcome && lhs.items == rhs.items
			&& lhs.messageIDs == rhs.messageIDs && lhs.pendingLine == rhs.pendingLine
			&& lhs.runningUsage?.input == rhs.runningUsage?.input
			&& lhs.runningUsage?.output == rhs.runningUsage?.output
	}

	/// Whether the line was a JSON event (applied, or of a kind not shown).
	@discardableResult
	private mutating func consume(_ line: Substring) -> Bool {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else {
			return true
		}
		guard let event = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
			return false
		}
		switch event["type"] as? String {
		case "system":
			if model == nil, let eventModel = event["model"] as? String {
				model = eventModel
			}
		case "assistant":
			guard let message = event["message"] as? [String: Any] else {
				break
			}
			if let id = message["id"] as? String {
				messageIDs.insert(id)
			}
			if let usage = message["usage"] as? [String: Any] {
				runningUsage = (Self.int(usage["input_tokens"]), Self.int(usage["output_tokens"]))
			}
			for block in message["content"] as? [[String: Any]] ?? [] {
				appendAssistantBlock(block)
			}
		case "user":
			let message = event["message"] as? [String: Any]
			for block in message?["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_result" {
				guard let toolID = block["tool_use_id"] as? String, let index = toolIndices[toolID],
				      case var .tool(tool) = items[index]
				else {
					continue
				}
				tool.result = Self.resultText(block["content"])
				items[index] = .tool(tool)
			}
		case "result":
			let usage = event["usage"] as? [String: Any] ?? [:]
			outcome = Outcome(
				isError: event["is_error"] as? Bool ?? false,
				costUsd: Self.double(event["total_cost_usd"]),
				inputTokens: Self.int(usage["input_tokens"]),
				outputTokens: Self.int(usage["output_tokens"]),
				cacheReadTokens: Self.int(usage["cache_read_input_tokens"]),
				cacheCreationTokens: Self.int(usage["cache_creation_input_tokens"]),
				durationMs: Self.double(event["duration_ms"]),
				apiDurationMs: Self.double(event["duration_api_ms"]),
				turns: Self.int(event["num_turns"])
			)
		default:
			break
		}
		return true
	}

	private mutating func appendAssistantBlock(_ block: [String: Any]) {
		switch block["type"] as? String {
		case "text":
			guard let text = block["text"] as? String,
			      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			else {
				return
			}
			items.append(.message(id: "message-\(items.count)", text: text))
		case "tool_use":
			guard let id = block["id"] as? String, toolIndices[id] == nil else {
				return
			}
			let input = block["input"] ?? [String: Any]()
			toolIndices[id] = items.count
			items.append(.tool(Tool(
				id: id,
				name: block["name"] as? String ?? "tool",
				input: Self.json(input, pretty: true),
				inputPreview: String(Self.json(input, pretty: false).prefix(80)),
				result: nil
			)))
		default:
			break
		}
	}

	/// A tool result as text: a string as it is, the usual list of text blocks joined, anything
	/// else as indented JSON.
	private static func resultText(_ content: Any?) -> String {
		switch content {
		case let text as String:
			return text
		case let blocks as [[String: Any]] where blocks.allSatisfy({ $0["type"] as? String == "text" }):
			return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
		case let .some(value):
			return json(value, pretty: true)
		case .none:
			return ""
		}
	}

	private static func json(_ value: Any, pretty: Bool) -> String {
		guard JSONSerialization.isValidJSONObject(value) else {
			return String(describing: value)
		}
		var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
		if pretty {
			options.insert(.prettyPrinted)
		}
		return (try? JSONSerialization.data(withJSONObject: value, options: options))
			.flatMap { String(data: $0, encoding: .utf8) } ?? ""
	}

	private static func int(_ value: Any?) -> Int {
		(value as? NSNumber)?.intValue ?? 0
	}

	private static func double(_ value: Any?) -> Double {
		(value as? NSNumber)?.doubleValue ?? 0
	}
}
