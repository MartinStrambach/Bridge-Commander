import CoreGraphics
import Foundation

/// The MCP tools: their schemas, and what a call does.
enum SimulatorMCPTools {
	static let definitions: [JSONValue] = [
		tool(
			"list_devices",
			"List the iOS simulators, booted first, with their UDIDs and screen sizes in points. The one marked [shown] is in Bridge Commander's pane and is what the other tools act on by default.",
			properties: [:],
			readOnly: true
		),
		tool(
			"select_device",
			"Show a simulator in Bridge Commander's pane and make it the default for the other tools.",
			properties: ["udid": udidProperty("The simulator to show.")],
			required: ["udid"]
		),
		tool(
			"screenshot",
			"Capture the simulator's screen. The image is in points (one image pixel per point), so its coordinates are the ones tap and swipe take.",
			properties: ["udid": optionalUdid],
			readOnly: true
		),
		tool(
			"describe_ui",
			"List the frontmost app's accessibility elements — role, label, value, identifier and frame in points — as an indented tree. Faster and more exact than reading a screenshot for finding what to tap: tap the centre of an element's frame. With x and y, describes just the element at that point.",
			properties: [
				"x": number("Optional: describe only the element at this x, in points."),
				"y": number("Optional: describe only the element at this y, in points."),
				"udid": optionalUdid,
			],
			readOnly: true
		),
		tool(
			"tap",
			"Tap the screen at (x, y) in points, origin top left. Give duration_ms for a long press.",
			properties: [
				"x": number("Horizontal position in points."),
				"y": number("Vertical position in points."),
				"duration_ms": number("How long to hold, in milliseconds. Default 60; 600 or more for a long press."),
				"udid": optionalUdid,
			],
			required: ["x", "y"]
		),
		tool(
			"swipe",
			"Drag one finger from one point to another, in points: scrolls, swipes, pulls to refresh. To scroll content down, swipe upwards (from a larger y to a smaller one).",
			properties: [
				"from_x": number("Start x in points."),
				"from_y": number("Start y in points."),
				"to_x": number("End x in points."),
				"to_y": number("End y in points."),
				"duration_ms": number("How long the drag takes, in milliseconds. Default 300; shorter flings further."),
				"udid": optionalUdid,
			],
			required: ["from_x", "from_y", "to_x", "to_y"]
		),
		tool(
			"pinch",
			"Two-finger pinch about (x, y) in points: scale above 1 spreads the fingers (zoom in), below 1 closes them (zoom out). rotation_degrees turns the fingers as they move, clockwise, for rotate gestures (use scale 1 to only rotate).",
			properties: [
				"x": number("Centre x in points."),
				"y": number("Centre y in points."),
				"scale": number("How far the fingers spread: 2 doubles their distance, 0.5 halves it."),
				"rotation_degrees": number("Optional rotation, clockwise. Default 0."),
				"duration_ms": number("How long the gesture takes, in milliseconds. Default 400."),
				"udid": optionalUdid,
			],
			required: ["x", "y", "scale"]
		),
		tool(
			"two_finger_drag",
			"Drag two fingers side by side from one point to another, in points — for gestures that need two fingers, such as tilting a map or two-finger scrolling.",
			properties: [
				"from_x": number("Start x in points (midway between the fingers)."),
				"from_y": number("Start y in points."),
				"to_x": number("End x in points."),
				"to_y": number("End y in points."),
				"spacing": number("Distance between the fingers in points. Default 40."),
				"duration_ms": number("How long the drag takes, in milliseconds. Default 400."),
				"udid": optionalUdid,
			],
			required: ["from_x", "from_y", "to_x", "to_y"]
		),
		tool(
			"type_text",
			"Type text into the focused field with the hardware keyboard (US layout, ASCII only). Tap the field first. \"\\n\" presses return.",
			properties: ["text": ["type": "string", "description": "The text to type."], "udid": optionalUdid],
			required: ["text"]
		),
		tool(
			"press_key",
			"Press a key, optionally with modifiers joined by \"+\": e.g. \"return\", \"delete\", \"escape\", \"tab\", \"up\", \"cmd+a\", \"cmd+v\", \"shift+tab\". Named keys: \(SimulatorKeyboardMap.namedKeyList.joined(separator: ", ")); any single character also works.",
			properties: ["key": ["type": "string", "description": "The key to press."], "udid": optionalUdid],
			required: ["key"]
		),
		tool(
			"press_button",
			"Press a hardware button. \"home\" goes to the home screen; \"lock\" locks or wakes the device.",
			properties: [
				"button": [
					"type": "string",
					"enum": .array(SimulatorHardwareButton.allCases.map { .string($0.rawValue) }),
					"description": "The button.",
				],
				"udid": optionalUdid,
			],
			required: ["button"]
		),
		tool(
			"rotate",
			"Turn the device to an orientation. The app's interface follows if it supports that orientation (an iPhone home screen and portrait-only apps stay portrait). Screenshots, tap/swipe coordinates and describe_ui frames all follow the interface, so take a new screenshot after rotating.",
			properties: [
				"orientation": [
					"type": "string",
					"enum": .array(SimulatorDeviceOrientation.allCases.map { .string($0.rawValue) }),
					"description": "landscape_left has the top of the device on the left, landscape_right on the right.",
				],
				"udid": optionalUdid,
			],
			required: ["orientation"]
		),
	]

	/// Runs a tool and returns its `CallToolResult`. Failures are reported in the result
	/// (`isError`), as MCP asks, so the model sees what went wrong.
	static func call(
		name: String,
		arguments: JSONValue,
		actions: any SimulatorToolActions,
		reportActivity: @Sendable (String) -> Void
	) async -> JSONValue {
		do {
			switch name {
			case "list_devices":
				return text(try await listDevices(actions: actions))

			case "select_device":
				let udid = try string(arguments, "udid")
				guard let device = try await actions.devices().first(where: { $0.id.caseInsensitiveCompare(udid) == .orderedSame }) else {
					throw SimulatorError.deviceNotFound(udid)
				}
				await actions.select(device)
				reportActivity(device.id)
				let note = device.isBooted ? "" : " It is not booted; boot it with `xcrun simctl boot \(device.id)`."
				return text("Showing \(device.name) (\(device.runtimeName)).\(note)")

			case "screenshot":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let jpeg = try await actions.screenshotJPEG(device: device)
				let size = device.screenPointSize
				let rotation = device.rotation == .upright ? "" : " (\(device.rotation.label))"
				return [
					"content": [
						["type": "image", "data": .string(jpeg.base64EncodedString()), "mimeType": "image/jpeg"],
						["type": "text", "text": .string("\(device.name), \(Int(size.width))×\(Int(size.height)) points\(rotation).")],
					],
				]

			case "describe_ui":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				if let x = arguments["x"]?.doubleValue, let y = arguments["y"]?.doubleValue {
					guard let element = try await actions.accessibilityElement(device: device, at: CGPoint(x: x, y: y)) else {
						return text("No accessibility element at (\(format(x)), \(format(y))).")
					}
					return text(SimulatorAccessibilityFormatter.describe(element: element))
				}
				return text(SimulatorAccessibilityFormatter.describe(tree: try await actions.accessibilityTree(device: device)))

			case "pinch":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let center = try CGPoint(x: number(arguments, "x"), y: number(arguments, "y"))
				let scale = try number(arguments, "scale")
				guard scale > 0 else {
					throw ToolError("\"scale\" must be greater than 0.")
				}
				let rotation = arguments["rotation_degrees"]?.doubleValue ?? 0
				let fingers = SimulatorHost.pinchFingers(center: center, scale: scale, rotationDegrees: rotation)
				let duration = milliseconds(arguments, "duration_ms", default: 400, range: 100...5000)
				try await actions.twoFingerGesture(device: device, from: fingers.start, to: fingers.end, duration: duration)
				return text("Pinched about (\(format(center.x)), \(format(center.y))) by \(format(scale))×\(rotation == 0 ? "" : ", rotating \(format(rotation))°").")

			case "two_finger_drag":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let from = try CGPoint(x: number(arguments, "from_x"), y: number(arguments, "from_y"))
				let to = try CGPoint(x: number(arguments, "to_x"), y: number(arguments, "to_y"))
				let half = min(max(arguments["spacing"]?.doubleValue ?? 40, 10), 200) / 2
				let duration = milliseconds(arguments, "duration_ms", default: 400, range: 50...5000)
				try await actions.twoFingerGesture(
					device: device,
					from: FingerPair(CGPoint(x: from.x - half, y: from.y), CGPoint(x: from.x + half, y: from.y)),
					to: FingerPair(CGPoint(x: to.x - half, y: to.y), CGPoint(x: to.x + half, y: to.y)),
					duration: duration
				)
				return text("Dragged two fingers from (\(format(from.x)), \(format(from.y))) to (\(format(to.x)), \(format(to.y))).")

			case "tap":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let x = try number(arguments, "x")
				let y = try number(arguments, "y")
				let hold = milliseconds(arguments, "duration_ms", default: 60, range: 10...10000)
				try await actions.tap(device: device, x: x, y: y, holdFor: hold)
				return text("Tapped (\(format(x)), \(format(y))).")

			case "swipe":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let from = try CGPoint(x: number(arguments, "from_x"), y: number(arguments, "from_y"))
				let to = try CGPoint(x: number(arguments, "to_x"), y: number(arguments, "to_y"))
				let duration = milliseconds(arguments, "duration_ms", default: 300, range: 50...5000)
				try await actions.swipe(device: device, from: from, to: to, duration: duration)
				return text("Swiped from (\(format(from.x)), \(format(from.y))) to (\(format(to.x)), \(format(to.y))).")

			case "type_text":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let value = try string(arguments, "text")
				try await actions.type(device: device, text: value)
				return text("Typed \(value.count) characters.")

			case "press_key":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let key = try string(arguments, "key")
				guard let stroke = SimulatorKeyboardMap.keyStroke(named: key) else {
					throw SimulatorError.unknownKey(key)
				}
				try await actions.press(device: device, key: stroke)
				return text("Pressed \(key).")

			case "press_button":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let name = try string(arguments, "button")
				guard let button = SimulatorHardwareButton(rawValue: name) else {
					throw ToolError("Unknown button \"\(name)\".")
				}
				try await actions.press(device: device, button: button)
				return text("Pressed \(name).")

			case "rotate":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let name = try string(arguments, "orientation")
				guard let orientation = SimulatorDeviceOrientation(rawValue: name) else {
					throw ToolError("Unknown orientation \"\(name)\".")
				}
				let rotated = try await actions.rotate(device: device, to: orientation)
				return text(rotationReport(rotated, orientation: orientation))

			default:
				return text("Unknown tool \(name).", isError: true)
			}
		}
		catch {
			return text(error.localizedDescription, isError: true)
		}
	}

	private static func listDevices(actions: any SimulatorToolActions) async throws -> String {
		let devices = try await actions.devices()
		guard !devices.isEmpty else {
			return "No iOS simulators are installed."
		}
		let selected = actions.selectedDeviceId
		return devices.map { device in
			let size = device.screenPointSize
			let shown = device.id == selected ? " [shown]" : ""
			let rotation = device.rotation == .upright ? "" : " \(device.rotation.label)"
			return "\(device.name) (\(device.runtimeName)) \(device.id) — \(device.state.label), \(Int(size.width))×\(Int(size.height)) pt\(rotation)\(shown)"
		}
		.joined(separator: "\n")
	}

	/// What a rotation did, including when the interface did not follow the device.
	private static func rotationReport(_ device: SimulatorDevice, orientation: SimulatorDeviceOrientation) -> String {
		let size = device.screenPointSize
		let points = "\(Int(size.width))×\(Int(size.height)) points"
		guard device.rotation == orientation.screenRotation else {
			return "Turned the device to \(orientation.label), but the interface stayed \(device.rotation.label) — the app does not support that orientation. The screen is \(points)."
		}
		return "Rotated to \(orientation.label). The screen is now \(points); take a new screenshot before using coordinates."
	}

	/// The device a call addresses, reported so the pane can come up showing it.
	private static func device(
		for arguments: JSONValue,
		actions: any SimulatorToolActions,
		reportActivity: @Sendable (String) -> Void
	) async throws -> SimulatorDevice {
		let device = try await actions.resolveDevice(udid: arguments["udid"]?.stringValue)
		reportActivity(device.id)
		return device
	}

	// MARK: - Arguments

	private struct ToolError: LocalizedError {
		let message: String

		init(_ message: String) {
			self.message = message
		}

		var errorDescription: String? {
			message
		}
	}

	private static func string(_ arguments: JSONValue, _ key: String) throws -> String {
		guard let value = arguments[key]?.stringValue else {
			throw ToolError("Missing \"\(key)\".")
		}
		return value
	}

	private static func number(_ arguments: JSONValue, _ key: String) throws -> Double {
		guard let value = arguments[key]?.doubleValue, value.isFinite else {
			throw ToolError("Missing or non-numeric \"\(key)\".")
		}
		return value
	}

	private static func milliseconds(_ arguments: JSONValue, _ key: String, default value: Double, range: ClosedRange<Double>) -> Duration {
		let requested = arguments[key]?.doubleValue ?? value
		return .milliseconds(Int(min(max(requested, range.lowerBound), range.upperBound)))
	}

	private static func format(_ value: Double) -> String {
		value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
	}

	// MARK: - Building results and schemas

	private static func text(_ message: String, isError: Bool = false) -> JSONValue {
		["content": [["type": "text", "text": .string(message)]], "isError": .bool(isError)]
	}

	private static let optionalUdid = udidProperty("Which simulator. Defaults to the one shown in Bridge Commander, or else a booted one.")

	private static func udidProperty(_ description: String) -> JSONValue {
		["type": "string", "description": .string(description)]
	}

	private static func number(_ description: String) -> JSONValue {
		["type": "number", "description": .string(description)]
	}

	private static func tool(
		_ name: String,
		_ description: String,
		properties: [String: JSONValue],
		required: [String] = [],
		readOnly: Bool = false
	) -> JSONValue {
		var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
		if !required.isEmpty {
			schema["required"] = .array(required.map { .string($0) })
		}
		return [
			"name": .string(name),
			"description": .string(description),
			"inputSchema": .object(schema),
			"annotations": ["readOnlyHint": .bool(readOnly), "openWorldHint": false],
		]
	}
}
