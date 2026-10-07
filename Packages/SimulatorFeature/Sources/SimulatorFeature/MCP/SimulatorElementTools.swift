import CoreGraphics
import Foundation

/// `press_element`, `set_value` and `scroll_to_element`: reading their arguments and wording what
/// happened. Kept apart from `SimulatorMCPTools` so the coordinate tools there stay one screen.
nonisolated enum SimulatorElementTools {
	static let names: Set<String> = ["press_element", "set_value", "scroll_to_element"]

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
		"role": [
			"type": "string",
			"description": "Optional: only elements with this role, as describe_ui shows it (Button, TextField, Switch…).",
		],
		"index": [
			"type": "integer",
			"description": "Which of several matches, from 0 in describe_ui order. Without it, several matches are listed instead of acted on.",
		],
	]

	/// The reply text for one call, the element having been found and acted on through `actions`.
	static func call(
		name: String,
		arguments: JSONValue,
		device: SimulatorDevice,
		actions: any SimulatorToolActions
	) async throws -> String {
		let action: SimulatorElementAction
		switch name {
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

		let outcome = try await actions.elementAction(action, on: query(from: arguments, for: action), device: device)
		return describe(outcome)
	}

	/// The query the arguments describe. `set_value` with nothing to go on looks among the text
	/// fields, so a screen with one field needs no identifier for it.
	static func query(from arguments: JSONValue, for action: SimulatorElementAction) throws -> SimulatorElementQuery {
		func text(_ key: String) -> String? {
			guard let value = arguments[key]?.stringValue, !value.isEmpty else {
				return nil
			}
			return value
		}

		var query = SimulatorElementQuery(identifier: text("identifier"), label: text("label"))
		if let role = text("role") {
			query.roles = [role]
		}
		if let index = arguments["index"]?.doubleValue {
			query.index = Int(index)
		}
		if query.identifier == nil, query.label == nil, query.roles.isEmpty {
			guard case .setValue = action else {
				throw SimulatorElementError.noCriteria
			}
			query.roles = SimulatorElementQuery.textEntryRoles
		}
		return query
	}

	static func describe(_ outcome: SimulatorElementOutcome) -> String {
		let element = SimulatorAccessibilityFormatter.line(for: outcome.element)
		switch outcome.effect {
		case .pressed:
			return "Pressed \(element) (AXPress)."
		case let .tappedCentre(point):
			return "Tapped the centre of \(element) at (\(Int(point.x.rounded())), \(Int(point.y.rounded()))): "
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
