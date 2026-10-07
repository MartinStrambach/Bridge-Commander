import Foundation

/// Waiting for the screen to settle after an action tool, so the model's next screenshot shows
/// the action's result instead of an animation midway — or the old screen.
extension SimulatorMCPTools {
	/// The argument every action tool takes.
	static let waitForSettleProperty: JSONValue = [
		"type": "boolean",
		"description": "Wait (up to 3 s) for the screen to stop changing before returning, and report how that went. Default true; false returns as soon as the input is delivered.",
	]

	/// Runs `action` and returns `message`, followed — unless the call asked not to wait — by how
	/// the screen settled. The screen is fingerprinted before the action so that a change already
	/// under way when the action returns still counts as its effect.
	static func performWaitingForSettle(
		_ message: String,
		device: SimulatorDevice,
		arguments: JSONValue,
		actions: any SimulatorToolActions,
		action: () async throws -> Void
	) async throws -> String {
		guard waitsForSettle(arguments) else {
			try await action()
			return message
		}
		let baseline = await actions.screenFingerprint(device: device)
		try await action()
		let result = await actions.waitForScreenToSettle(device: device, baseline: baseline)
		return "\(message) \(result.summary)"
	}

	/// `wait_for_settle`, true unless given as false — models occasionally quote booleans.
	static func waitsForSettle(_ arguments: JSONValue) -> Bool {
		switch arguments["wait_for_settle"] {
		case let .bool(value)?:
			value
		case let .string(value)?:
			value.lowercased() != "false"
		default:
			true
		}
	}
}
