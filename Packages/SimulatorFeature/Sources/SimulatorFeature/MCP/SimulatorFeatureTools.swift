import Foundation

/// `set_location`, `simulate_memory_warning`, `start_recording` and `stop_recording` — Simulator.app's
/// Features and File ▸ Record Screen. Kept apart from `SimulatorMCPTools`, like the element tools,
/// so the input tools there stay one screen.
nonisolated enum SimulatorFeatureTools {
	static let names: Set<String> = ["set_location", "simulate_memory_warning", "start_recording", "stop_recording"]

	static var definitions: [JSONValue] {
		let coordinate: JSONValue = [
			"type": "object",
			"properties": [
				"latitude": SimulatorMCPTools.number("Degrees, -90 to 90."),
				"longitude": SimulatorMCPTools.number("Degrees, -180 to 180."),
			],
			"required": ["latitude", "longitude"],
		]
		let limitMinutes = Int(SimulatorScreenRecorder.defaultLimit.components.seconds / 60)
		return [
			SimulatorMCPTools.tool(
				"set_location",
				"Simulate the device's location, as Simulator.app's Features ▸ Location does. Give exactly one of: latitude and longitude to stay at a point; waypoints to move along a route; a scenario; or clear to stop any route or scenario and drop the simulated location. Apps see the change through Core Location (they need location permission — grant it with `xcrun simctl privacy <udid> grant location <bundle id>`).",
				properties: [
					"latitude": SimulatorMCPTools.number("Latitude in degrees, with longitude."),
					"longitude": SimulatorMCPTools.number("Longitude in degrees, with latitude."),
					"waypoints": [
						"type": "array",
						"items": coordinate,
						"minItems": 2,
						"description": "A route of two or more points, moved along at speed with an update every second.",
					],
					"speed": SimulatorMCPTools.number("Speed along waypoints in metres per second. Default 20."),
					"scenario": [
						"type": "string",
						"description": .string("A built-in scenario: \(SimulatorLocationCommand.knownScenarios.map { "\"\($0)\"" }.joined(separator: ", ")) (`xcrun simctl location <udid> list` names the runtime's own)."),
					],
					"clear": ["type": "boolean", "description": "Stop any route or scenario and clear the simulated location."],
					"udid": SimulatorMCPTools.optionalUdid,
				]
			),
			SimulatorMCPTools.tool(
				"simulate_memory_warning",
				"Send a memory warning to the simulator's apps, as Simulator.app's Debug ▸ Simulate Memory Warning does: UIKit calls didReceiveMemoryWarning and posts UIApplication.didReceiveMemoryWarningNotification. For checking that an app frees caches and survives low memory.",
				properties: ["udid": SimulatorMCPTools.optionalUdid]
			),
			SimulatorMCPTools.tool(
				"start_recording",
				"Start recording a video of the simulator's screen (H.264 QuickTime .mov) — to show a flow or a bug to the user. Drive the app with the other tools meanwhile, then call stop_recording, which saves the file. Recording stops on its own after \(limitMinutes) minutes. One recording per simulator at a time.",
				properties: [
					"path": [
						"type": "string",
						"description": "Optional: an absolute path for the .mov, or a folder to save it in. Default: where Simulator.app saves screenshots (the Desktop unless set), named as Simulator.app names recordings.",
					],
					"udid": SimulatorMCPTools.optionalUdid,
				]
			),
			SimulatorMCPTools.tool(
				"stop_recording",
				"Stop the screen recording started with start_recording and save it. Returns the file's path and the recording's length.",
				properties: [
					"udid": SimulatorMCPTools.udidProperty("Which simulator's recording. Default: the only one recording, or else the one shown in Bridge Commander. It need not still be booted."),
				]
			),
		]
	}

	/// The reply text for one call.
	static func call(
		name: String,
		arguments: JSONValue,
		actions: any SimulatorToolActions,
		device: () async throws -> SimulatorDevice
	) async throws -> String {
		switch name {
		case "set_location":
			let device = try await device()
			let command = try locationCommand(from: arguments)
			try await actions.setLocation(device: device, command)
			return describe(command, on: device)

		case "simulate_memory_warning":
			let device = try await device()
			try await actions.simulateMemoryWarning(device: device)
			return "Sent a memory warning to the apps on \(device.name)."

		case "start_recording":
			let device = try await device()
			let url = try await actions.startRecording(device: device, path: arguments["path"]?.stringValue)
			let minutes = Int(SimulatorScreenRecorder.defaultLimit.components.seconds / 60)
			return "Recording \(device.name) to \(url.path(percentEncoded: false)). Call stop_recording to save it; it stops on its own after \(minutes) minutes."

		default:
			let recording = try await actions.stopRecording(udid: arguments["udid"]?.stringValue)
			let path = recording.url.path(percentEncoded: false)
			let length = seconds(recording.duration)
			guard let reason = recording.endedEarly else {
				return "Saved the recording (\(length) seconds) to \(path)."
			}
			return "The recording had already stopped — \(reason) — and was saved to \(path) (\(length) seconds)."
		}
	}

	/// The command the arguments describe: exactly one of a point, waypoints, a scenario or clear.
	static func locationCommand(from arguments: JSONValue) throws(SimulatorError) -> SimulatorLocationCommand {
		var commands: [SimulatorLocationCommand] = []
		let latitude = arguments["latitude"]?.doubleValue
		let longitude = arguments["longitude"]?.doubleValue
		switch (latitude, longitude) {
		case let (latitude?, longitude?):
			commands.append(.set(SimulatorCoordinate(latitude: latitude, longitude: longitude)))
		case (nil, nil):
			break
		default:
			throw .invalidLocation("Give both latitude and longitude.")
		}
		if let waypoints = arguments["waypoints"] {
			guard case let .array(points) = waypoints else {
				throw .invalidLocation("\"waypoints\" must be an array of {latitude, longitude}.")
			}
			let coordinates = try points.map { point throws(SimulatorError) in
				guard let latitude = point["latitude"]?.doubleValue, let longitude = point["longitude"]?.doubleValue else {
					throw .invalidLocation("Every waypoint needs a latitude and a longitude.")
				}
				return SimulatorCoordinate(latitude: latitude, longitude: longitude)
			}
			commands.append(.route(coordinates, speed: arguments["speed"]?.doubleValue))
		}
		if let scenario = arguments["scenario"]?.stringValue {
			commands.append(.scenario(scenario))
		}
		if SimulatorMCPTools.flag(arguments, "clear") {
			commands.append(.clear)
		}

		guard commands.count == 1, let command = commands.first else {
			throw .invalidLocation(commands.isEmpty
				? "Give latitude and longitude, waypoints, a scenario, or clear."
				: "Give only one of latitude and longitude, waypoints, a scenario, or clear.")
		}
		return command
	}

	private static func describe(_ command: SimulatorLocationCommand, on device: SimulatorDevice) -> String {
		switch command {
		case let .set(coordinate):
			return "\(device.name) is now at \(coordinate.simctlArgument.replacingOccurrences(of: ",", with: ", "))."
		case let .route(waypoints, speed):
			let metres = speed.map { String(format: "%g", $0) } ?? "20"
			return "\(device.name) is moving along \(waypoints.count) waypoints at \(metres) m/s, with an update every second. set_location with clear stops it."
		case let .scenario(name):
			return "\(device.name) is running the \"\(name)\" location scenario. set_location with clear stops it."
		case .clear:
			return "Cleared \(device.name)'s simulated location."
		}
	}

	private static func seconds(_ duration: Duration) -> String {
		let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
		return String(format: "%.1f", value)
	}
}
