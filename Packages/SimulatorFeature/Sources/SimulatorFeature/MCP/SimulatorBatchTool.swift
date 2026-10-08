import Foundation

/// `batch`: several tool calls in one, in order — AXe's `batch`. Each step is an ordinary call of
/// the tool it names, so it waits for the screen to settle as that tool does; what the model saves
/// is a turn per step.
nonisolated enum SimulatorBatchTool {
	/// What a step may be: the actions and the looks, not device management, crash reports or a
	/// nested batch.
	static let stepTools: [String] = [
		"tap", "swipe", "gesture", "pinch", "two_finger_drag", "type_text", "press_key", "press_button",
		"press_element", "set_value", "set_slider", "scroll_to_element", "wait_for_element", "rotate",
		"describe_ui", "screenshot", "sleep",
	]
	static let maximumSteps = 40
	static let maximumSleep = Duration.seconds(10)

	static var definition: JSONValue {
		SimulatorMCPTools.tool(
			"batch",
			"Run several steps in one call, in order, each as if its tool had been called — e.g. tap a field, type, press return, wait for the result, take a screenshot. Each step is an object with \"tool\" (one of \(stepTools.joined(separator: ", "))) and that tool's arguments; {\"tool\": \"sleep\", \"duration_ms\": 500} pauses. Every action step waits for the screen to settle as usual, and wait_for_element steps wait for what the next step needs. Stops at the first step that fails unless continue_on_error is set. Returns each step's result, and any screenshots taken.",
			properties: [
				"steps": [
					"type": "array",
					"items": [
						"type": "object",
						"properties": ["tool": ["type": "string", "enum": .array(stepTools.map { .string($0) })]],
						"required": ["tool"],
						"additionalProperties": true,
					],
					"minItems": 1,
					"maxItems": .number(Double(maximumSteps)),
					"description": "The steps, in order: {\"tool\": \"tap\", \"x\": 100, \"y\": 200}, {\"tool\": \"press_element\", \"label\": \"Next\"}, …",
				],
				"continue_on_error": ["type": "boolean", "description": "Run the later steps even after one fails. Default false."],
				"udid": SimulatorMCPTools.udidProperty("Which simulator every step acts on, unless a step names its own. Defaults to the one shown in Bridge Commander, or else a booted one."),
			],
			required: ["steps"]
		)
	}

	struct BatchError: LocalizedError {
		let errorDescription: String?
	}

	/// The batch's `CallToolResult`: a numbered line per step, then the steps' images. `run` makes
	/// one ordinary tool call.
	static func call(
		arguments: JSONValue,
		run: (_ tool: String, _ arguments: JSONValue) async -> JSONValue
	) async throws -> JSONValue {
		let steps = try parse(arguments)
		let continueOnError = SimulatorMCPTools.flag(arguments, "continue_on_error")

		var lines: [String] = []
		var images: [JSONValue] = []
		var failures = 0
		for (offset, step) in steps.enumerated() {
			let number = offset + 1
			if step.tool == "sleep" {
				let requested = step.arguments["duration_ms"]?.doubleValue ?? 500
				let duration = min(Duration.milliseconds(Int(max(requested, 0))), maximumSleep)
				try await Task.sleep(for: duration)
				lines.append("\(number). sleep: waited \(SimulatorElementTools.seconds(duration)) s.")
				continue
			}

			var stepArguments = step.arguments
			if stepArguments["udid"] == nil, let udid = arguments["udid"] {
				stepArguments["udid"] = udid
			}
			let result = await run(step.tool, .object(stepArguments))
			let failed = result["isError"] == .bool(true)
			let content: [JSONValue] = if case let .array(items)? = result["content"] { items } else { [] }
			let text = content.compactMap { $0["type"] == "text" ? $0["text"]?.stringValue : nil }.joined(separator: "\n")
			images += content.filter { $0["type"] == "image" }
			lines.append("\(number). \(step.tool)\(failed ? " FAILED" : ""): \(text)")

			if failed {
				failures += 1
				if !continueOnError {
					let skipped = steps.count - number
					if skipped > 0 {
						lines.append("Stopped at step \(number); the \(skipped == 1 ? "last step was" : "\(skipped) steps after it were") not run.")
					}
					break
				}
			}
		}

		let summary = failures == 0
			? "Ran \(steps.count) step\(steps.count == 1 ? "" : "s")."
			: "\(failures) of \(steps.count) steps failed."
		let report = ([summary] + lines).joined(separator: "\n")
		return [
			"content": .array([["type": "text", "text": .string(report)]] + images),
			"isError": .bool(failures > 0),
		]
	}

	/// Every step checked before any runs, so a misspelt tool does not leave the flow half done.
	private static func parse(_ arguments: JSONValue) throws -> [(tool: String, arguments: [String: JSONValue])] {
		guard case let .array(steps)? = arguments["steps"], !steps.isEmpty else {
			throw BatchError(errorDescription: "\"steps\" must be a non-empty array of {\"tool\": …, arguments…}.")
		}
		guard steps.count <= maximumSteps else {
			throw BatchError(errorDescription: "At most \(maximumSteps) steps in one batch; split it.")
		}
		return try steps.enumerated().map { offset, step in
			guard case var .object(fields) = step, let tool = fields["tool"]?.stringValue else {
				throw BatchError(errorDescription: "Step \(offset + 1) is not an object with a \"tool\".")
			}
			guard stepTools.contains(tool) else {
				throw BatchError(errorDescription: "Step \(offset + 1): \"\(tool)\" cannot be a batch step; use one of \(stepTools.joined(separator: ", ")).")
			}
			fields["tool"] = nil
			return (tool, fields)
		}
	}
}
