import Foundation

/// `launch_app`, `stop_app` and `open_url` — running apps with their output captured to a file
/// Claude can read, which a `simctl launch` in the terminal does not give.
nonisolated enum SimulatorAppTools {
	static let names: Set<String> = ["launch_app", "stop_app", "open_url"]

	static var definitions: [JSONValue] {
		let bundleId: JSONValue = ["type": "string", "description": "The app's bundle identifier."]
		return [
			SimulatorMCPTools.tool(
				"launch_app",
				"Launch an installed app, ending any copy already running, and capture what it prints (stdout, stderr: print, NSLog) and logs (os_log / Logger) into one file, which the reply names — read it with tail or grep while you use the app, to see its console as Xcode shows it. By default the log keeps the app's own subsystem (the bundle id, or one under it) plus every error and fault in its process; give log_predicate for other messages. The capture runs until the app exits. Install the app first with `xcrun simctl install <udid> <path to .app>`.",
				properties: [
					"bundle_id": bundleId,
					"arguments": ["type": "array", "items": ["type": "string"], "description": "Optional: launch arguments for the app (e.g. [\"-UITesting\", \"YES\"])."],
					"environment": [
						"type": "object",
						"additionalProperties": ["type": "string"],
						"description": "Optional: environment variables for the app.",
					],
					"capture_logs": ["type": "boolean", "description": "Capture output and log to a file. Default true."],
					"log_predicate": [
						"type": "string",
						"description": "Optional: a `log stream` predicate replacing the default, e.g. 'process == \"MyApp\"' for everything the process logs, or 'subsystem == \"com.example.network\"'.",
					],
					"udid": SimulatorMCPTools.optionalUdid,
				],
				required: ["bundle_id"]
			),
			SimulatorMCPTools.tool(
				"stop_app",
				"Terminate a running app, which also ends launch_app's capture of its output.",
				properties: ["bundle_id": bundleId, "udid": SimulatorMCPTools.optionalUdid],
				required: ["bundle_id"]
			),
			SimulatorMCPTools.tool(
				"open_url",
				"Open a URL in the simulator, as tapping a link does: a web page in Safari, a custom scheme (myapp://…) or universal link in the app that handles it — for testing deep links.",
				properties: [
					"url": ["type": "string", "description": "The URL, with its scheme."],
					"udid": SimulatorMCPTools.optionalUdid,
				],
				required: ["url"]
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
		case "launch_app":
			let request = try launchRequest(from: arguments)
			let device = try await device()
			let launch = try await actions.launchApp(device: device, request)
			let pid = launch.processId.map { " (pid \($0))" } ?? ""
			guard let url = launch.logURL else {
				return "Launched \(request.bundleId) on \(device.name)\(pid)."
			}
			return """
			Launched \(request.bundleId) on \(device.name)\(pid). Its output and log go to \(url.path(percentEncoded: false)) until it exits; read it with tail or grep.
			os_log messages kept: \(launch.logPredicate ?? "")
			"""

		case "stop_app":
			let bundleId = try string(arguments, "bundle_id")
			let device = try await device()
			let log = try await actions.terminateApp(device: device, bundleId: bundleId)
			let note = log.map { " Its captured output is in \($0.path(percentEncoded: false))." } ?? ""
			return "Terminated \(bundleId) on \(device.name).\(note)"

		default:
			let url = try string(arguments, "url")
			let device = try await device()
			try await actions.openURL(device: device, url)
			return "Opened \(url) on \(device.name). Take a screenshot to see what handled it."
		}
	}

	static func launchRequest(from arguments: JSONValue) throws(SimulatorError) -> SimulatorAppLaunchRequest {
		var request = try SimulatorAppLaunchRequest(bundleId: string(arguments, "bundle_id"))
		if let value = arguments["arguments"] {
			guard case let .array(items) = value else {
				throw .invalidArgument("\"arguments\" must be an array of strings.")
			}
			request.arguments = try items.map { item throws(SimulatorError) in
				guard let text = item.stringValue else {
					throw .invalidArgument("\"arguments\" must be an array of strings.")
				}
				return text
			}
		}
		if let value = arguments["environment"] {
			guard case let .object(variables) = value else {
				throw .invalidArgument("\"environment\" must be an object of strings.")
			}
			for (name, item) in variables {
				// Models sometimes send a number unquoted.
				guard let text = item.stringValue ?? item.doubleValue.map({ String(format: "%g", $0) }) else {
					throw .invalidArgument("\"environment\" values must be strings.")
				}
				request.environment[name] = text
			}
		}
		request.captureLogs = SimulatorMCPTools.flag(arguments, "capture_logs", default: true)
		request.logPredicate = arguments["log_predicate"]?.stringValue.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
		return request
	}

	private static func string(_ arguments: JSONValue, _ key: String) throws(SimulatorError) -> String {
		guard let value = arguments[key]?.stringValue, !value.isEmpty else {
			throw .invalidArgument("Missing \"\(key)\".")
		}
		return value
	}
}
