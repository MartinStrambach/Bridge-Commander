import CoreGraphics
import Foundation

/// `press_element`, `set_value`, `scroll_to_element`, `wait_for_element` and `set_slider`: reading
/// their arguments and wording what happened. Kept apart from `SimulatorMCPTools` so the coordinate
/// tools there stay one screen.
nonisolated enum SimulatorElementTools {
	static let names: Set<String> = ["press_element", "set_value", "scroll_to_element", "wait_for_element", "set_slider"]

	/// The schema properties every element tool shares.
	static let queryProperties: [String: JSONValue] = [
		"identifier": [
			"type": "string",
			"description": "The element's accessibility identifier (id= in describe_ui), matched exactly. Tried before label.",
		],
		"label": [
			"type": "string",
			"description": "The element's label: an exact match wins, then one ignoring case, then labels containing this text.",
		],
		"current_value": [
			"type": "string",
			"description": "The element's current value (value= in describe_ui), matched like label and tried after it — e.g. a field's text, or \"1\" for a switch that is on.",
		],
		"role": [
			"type": "string",
			"description": "Optional: only elements with this role, as describe_ui shows it (Button, TextField, Switch…).",
		],
		"index": [
			"type": "integer",
			"description": "Which of several matches, from 0 in describe_ui order. Without it, several matches are listed instead of acted on.",
		],
	]

	/// `timeout_ms` of the tools that act on an element.
	static let timeoutProperty: JSONValue = [
		"type": "number",
		"description": "Optional: wait up to this long, in milliseconds, for the element to appear before giving up — for a screen still loading or animating in. Default 0.",
	]

	static var definitions: [JSONValue] {
		[
			SimulatorMCPTools.tool(
				"wait_for_element",
				"Wait until an element found by identifier, label or value is on screen — or, with gone, until it is no longer — re-reading the accessibility tree every 300 ms. For loading screens, spinners and transitions, instead of sleeping or taking screenshots until something shows up.",
				properties: queryProperties.merging([
					"gone": ["type": "boolean", "description": "Wait for the element to disappear instead. Default false."],
					"timeout_ms": SimulatorMCPTools.number("How long to wait at most, in milliseconds. Default 10000, at most 60000."),
					"udid": SimulatorMCPTools.optionalUdid,
				]) { $1 },
				readOnly: true
			),
			SimulatorMCPTools.tool(
				"set_slider",
				"Move a slider found by identifier or label (or the screen's only slider) to a position from 0 to 100 %: drags its thumb, reads the value back and corrects, then steps with accessibility increments when the slider moves in steps. Reports the value it ends on — a stepped slider stops at the step nearest the target.",
				properties: queryProperties.merging([
					"value": SimulatorMCPTools.number("Where to put it, in percent of its range: 0 to 100."),
					"timeout_ms": timeoutProperty,
					"udid": SimulatorMCPTools.optionalUdid,
				]) { $1 },
				required: ["value"]
			),
		]
	}

	/// The reply text for one call, the element having been found and acted on through `actions`.
	static func call(
		name: String,
		arguments: JSONValue,
		device: SimulatorDevice,
		actions: any SimulatorToolActions
	) async throws -> String {
		let action: SimulatorElementAction
		switch name {
		case "wait_for_element":
			return try await waitForElement(arguments: arguments, device: device, actions: actions)
		case "set_slider":
			return try await SimulatorSliderTool.call(
				arguments: arguments,
				query: query(from: arguments, defaultRoles: SimulatorElementQuery.adjustableRoles),
				timeout: timeout(arguments, default: 0),
				device: device,
				actions: actions
			)
		case "set_value":
			guard let value = arguments["value"]?.stringValue else {
				throw SimulatorElementError.missingValue
			}
			action = .setValue(value)
		case "scroll_to_element":
			action = .scrollToVisible
		default:
			action = .press
		}

		let query = try query(from: arguments, defaultRoles: isSetValue(action) ? SimulatorElementQuery.textEntryRoles : nil)
		let settles = SimulatorMCPTools.waitsForSettle(arguments)
		var baseline: ScreenFingerprint?
		// Not `performWaitingForSettle`: the message depends on what the action did. The baseline
		// is retaken before each attempt, so a screen that finished loading while the element was
		// awaited does not count as the action's effect.
		let outcome = try await untilFound(timeout: timeout(arguments, default: 0)) {
			if settles {
				baseline = await actions.screenFingerprint(device: device)
			}
			return try await actions.elementAction(action, on: query, device: device)
		}
		guard settles else {
			return describe(outcome)
		}
		let settled = await actions.waitForScreenToSettle(device: device, baseline: baseline)
		return "\(describe(outcome)) \(settled.summary)"
	}

	private static func isSetValue(_ action: SimulatorElementAction) -> Bool {
		if case .setValue = action {
			return true
		}
		return false
	}

	/// The query the arguments describe. With nothing to go on, `defaultRoles` (a tool's own kind
	/// of element: text fields for `set_value`) stand in, so a screen with one such element needs
	/// no identifier for it; without them that is an error.
	static func query(from arguments: JSONValue, defaultRoles: Set<String>? = nil) throws -> SimulatorElementQuery {
		func text(_ key: String) -> String? {
			guard let value = arguments[key]?.stringValue, !value.isEmpty else {
				return nil
			}
			return value
		}

		var query = SimulatorElementQuery(identifier: text("identifier"), label: text("label"), value: text("current_value"))
		if let role = text("role") {
			query.roles = [role]
		}
		if let index = arguments["index"]?.doubleValue {
			query.index = Int(index)
		}
		if query.identifier == nil, query.label == nil, query.value == nil, query.roles.isEmpty {
			guard let defaultRoles else {
				throw SimulatorElementError.noCriteria
			}
			query.roles = defaultRoles
		}
		return query
	}

	// MARK: - Waiting

	/// Polled this often while an element is awaited; each poll walks the tree.
	static let pollInterval = Duration.milliseconds(300)

	/// `timeout_ms`, capped at a minute.
	static func timeout(_ arguments: JSONValue, default milliseconds: Double) -> Duration {
		let requested = arguments["timeout_ms"]?.doubleValue ?? milliseconds
		return .milliseconds(Int(min(max(requested, 0), 60_000)))
	}

	/// Runs `body` until it does not fail with `notFound`, or until `timeout` has passed — after
	/// which the last `notFound`, listing what is on screen, is thrown.
	static func untilFound<T>(timeout: Duration, _ body: () async throws -> T) async throws -> T {
		let clock = ContinuousClock()
		let deadline = clock.now + timeout
		while true {
			do {
				return try await body()
			}
			catch let error as SimulatorElementError {
				guard case .notFound = error, clock.now + pollInterval <= deadline else {
					throw error
				}
				try await Task.sleep(for: pollInterval)
			}
		}
	}

	private static func waitForElement(arguments: JSONValue, device: SimulatorDevice, actions: any SimulatorToolActions) async throws -> String {
		let query = try query(from: arguments)
		let untilGone = SimulatorMCPTools.flag(arguments, "gone")
		let timeout = timeout(arguments, default: 10_000)
		let clock = ContinuousClock()
		let start = clock.now

		while true {
			let candidates = try await actions.accessibilityTree(device: device).flattened()
			var matches = query.matches(in: candidates)
			if let index = query.index {
				matches = matches.indices.contains(index) ? [matches[index]] : []
			}
			let waited = seconds(clock.now - start)

			if untilGone, matches.isEmpty {
				return "No element matches \(query.summary) after \(waited) s."
			}
			if !untilGone, let first = matches.first {
				let element = SimulatorAccessibilityFormatter.line(for: candidates[first])
				let others = matches.count > 1 ? " (and \(matches.count - 1) more matching)" : ""
				return "Found \(element)\(others) after \(waited) s."
			}
			guard clock.now - start + pollInterval <= timeout else {
				if untilGone {
					let element = SimulatorAccessibilityFormatter.line(for: candidates[matches[0]])
					throw SimulatorElementError.timedOut("\(element) is still on screen after \(waited) s.")
				}
				// `match` words the miss with what is on screen.
				do {
					_ = try query.match(in: candidates)
				}
				catch {
					throw SimulatorElementError.timedOut("Waited \(waited) s. \(error.localizedDescription)")
				}
				throw SimulatorElementError.timedOut("No element matches \(query.summary) after \(waited) s.")
			}
			try await Task.sleep(for: pollInterval)
		}
	}

	static func seconds(_ duration: Duration) -> String {
		let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
		return String(format: "%.1f", value)
	}

	// MARK: - Replies

	static func describe(_ outcome: SimulatorElementOutcome) -> String {
		let element = SimulatorAccessibilityFormatter.line(for: outcome.element)
		switch outcome.effect {
		case .pressed:
			return "Pressed \(element) (AXPress)."
		case let .tapped(point):
			return "Tapped \(element) at (\(Int(point.x.rounded())), \(Int(point.y.rounded()))): "
				+ "it has no accessibility press, or refused it."
		case let .valueSet(readBack):
			guard let readBack else {
				return "Set the value of \(element)."
			}
			return "Set the value of \(element); it now reads \"\(readBack)\"."
		case let .scrolled(frame):
			return "Scrolled \(element) into view; its frame is now "
				+ "(\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded())))."
		}
	}
}
