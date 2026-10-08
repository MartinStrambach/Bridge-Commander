import CoreGraphics
import Foundation

/// The MCP tools: their schemas, and what a call does.
enum SimulatorMCPTools {
	static let definitions: [JSONValue] = inputDefinitions + SimulatorFeatureTools.definitions

	private static let inputDefinitions: [JSONValue] = [
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
				"wait_for_settle": waitForSettleProperty,
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
				"wait_for_settle": waitForSettleProperty,
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
				"wait_for_settle": waitForSettleProperty,
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
				"wait_for_settle": waitForSettleProperty,
			],
			required: ["from_x", "from_y", "to_x", "to_y"]
		),
		tool(
			"type_text",
			"Type text into the focused field with the hardware keyboard (US layout, ASCII only). Tap the field first. \"\\n\" presses return.",
			properties: ["text": ["type": "string", "description": "The text to type."], "udid": optionalUdid, "wait_for_settle": waitForSettleProperty],
			required: ["text"]
		),
		tool(
			"press_key",
			"Press a key, or several one after another, each optionally with modifiers joined by \"+\": e.g. \"return\", \"delete\", \"escape\", \"tab\", \"up\", \"cmd+a\", \"cmd+v\", \"shift+tab\". Named keys: \(SimulatorKeyboardMap.namedKeyList.joined(separator: ", ")); any single character also works. Give key for one, keys for a sequence (e.g. [\"cmd+a\", \"delete\"]).",
			properties: [
				"key": ["type": "string", "description": "The key to press."],
				"keys": ["type": "array", "items": ["type": "string"], "description": "Keys to press in order, instead of key."],
				"udid": optionalUdid,
				"wait_for_settle": waitForSettleProperty,
			]
		),
		tool(
			"press_button",
			"Press a hardware button. \"home\" goes to the home screen; \"lock\" (the same as \"side_button\") locks or wakes the device; \"play_pause\" toggles media playback. Hold one with duration_ms: about 1500 on the side button brings up Siri. There is no Apple Pay button: the simulator's input service has none.",
			properties: [
				"button": [
					"type": "string",
					"enum": .array(SimulatorHardwareButton.allCases.map { .string($0.rawValue) }),
					"description": "The button.",
				],
				"duration_ms": number("How long to hold it, in milliseconds. Default 100."),
				"udid": optionalUdid,
				"wait_for_settle": waitForSettleProperty,
			],
			required: ["button"]
		),
		tool(
			"press_element",
			"Press an element found by identifier or label rather than by position: the accessibility press (AXPress), or a tap on its centre if it has none. Lists the candidates when nothing or several match. Check the result afterwards — AXPress reports success even on elements that ignore it.",
			properties: SimulatorElementTools.queryProperties.merging(["udid": optionalUdid, "wait_for_settle": waitForSettleProperty]) { $1 }
		),
		tool(
			"set_value",
			"Set a text field's contents through accessibility, replacing what is there, without tapping or typing. With no identifier, label or role it looks among the text fields. If the element does not take a value, tap it and use type_text instead.",
			properties: SimulatorElementTools.queryProperties.merging([
				"value": ["type": "string", "description": "The new text."],
				"udid": optionalUdid,
				"wait_for_settle": waitForSettleProperty,
			]) { $1 },
			required: ["value"]
		),
		tool(
			"scroll_to_element",
			"Scroll the enclosing lists until an element found by identifier or label is fully on screen (AXScrollToVisible) — for one that is cut off or under a toolbar. Only elements describe_ui lists can be found; to reach rows further down, swipe.",
			properties: SimulatorElementTools.queryProperties.merging(["udid": optionalUdid, "wait_for_settle": waitForSettleProperty]) { $1 }
		),
		tool(
			"list_crashes",
			"List recent crash reports of apps in the simulator, newest first: time, app, bundle id, exception and a short reason, and the report's file name for crash_report. Crashes of the simulator's own processes (PosterBoard, daemons) are left out unless include_system is set.",
			properties: [
				"bundle_id": ["type": "string", "description": "Optional: only this app's crashes."],
				"since_minutes": number("How far back to look, in minutes. Default 60."),
				"limit": number("How many to list at most. Default 10."),
				"include_system": ["type": "boolean", "description": "Also list crashes of the simulator's own processes. Default false."],
				"udid": udidProperty("Which simulator. Defaults to the one shown in Bridge Commander, or else a booted one; it need not be booted."),
			],
			readOnly: true
		),
		tool(
			"crash_report",
			"Summarise one crash report: app and version, time, exception type, codes and signal, termination reason, the crash message from the simulator's log (an uncaught exception's reason, a Swift fatal error) and the symbolicated backtrace of the crashed thread.",
			properties: ["name": ["type": "string", "description": "The report's file name, as list_crashes gives it."]],
			required: ["name"],
			readOnly: true
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
		tool(
			"set_fold",
			"Open (unfold) or close (fold) a device that folds — the iPhone Duo. Closed, it shows its cover screen; open, the larger inner panel. Screenshots, tap/swipe coordinates and describe_ui all follow the panel shown, so take a new screenshot after. list_devices says which devices fold and how they are. Closing may lock the device, as shutting a real one does: if the cover then shows a dim screen that does not change, press_button side_button wakes it and a swipe up unlocks it.",
			properties: [
				"state": [
					"type": "string",
					"enum": .array(SimulatorFold.allCases.map { .string($0.rawValue) }),
					"description": "open shows the inner panel, closed the cover screen.",
				],
				"udid": optionalUdid,
			],
			required: ["state"]
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
				let fold = device.fold == .open ? " The device is unfolded; this is its inner panel." : ""
				return [
					"content": [
						["type": "image", "data": .string(jpeg.base64EncodedString()), "mimeType": "image/jpeg"],
						["type": "text", "text": .string("\(device.name), \(Int(size.width))×\(Int(size.height)) points\(rotation).\(fold)")],
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
				return text(try await performWaitingForSettle(
					"Pinched about (\(format(center.x)), \(format(center.y))) by \(format(scale))×\(rotation == 0 ? "" : ", rotating \(format(rotation))°").",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.twoFingerGesture(device: device, from: fingers.start, to: fingers.end, duration: duration)
				})

			case "two_finger_drag":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let from = try CGPoint(x: number(arguments, "from_x"), y: number(arguments, "from_y"))
				let to = try CGPoint(x: number(arguments, "to_x"), y: number(arguments, "to_y"))
				let half = min(max(arguments["spacing"]?.doubleValue ?? 40, 10), 200) / 2
				let duration = milliseconds(arguments, "duration_ms", default: 400, range: 50...5000)
				return text(try await performWaitingForSettle(
					"Dragged two fingers from (\(format(from.x)), \(format(from.y))) to (\(format(to.x)), \(format(to.y))).",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.twoFingerGesture(
						device: device,
						from: FingerPair(CGPoint(x: from.x - half, y: from.y), CGPoint(x: from.x + half, y: from.y)),
						to: FingerPair(CGPoint(x: to.x - half, y: to.y), CGPoint(x: to.x + half, y: to.y)),
						duration: duration
					)
				})

			case "tap":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let x = try number(arguments, "x")
				let y = try number(arguments, "y")
				let hold = milliseconds(arguments, "duration_ms", default: 60, range: 10...10000)
				return text(try await performWaitingForSettle(
					"Tapped (\(format(x)), \(format(y))).",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.tap(device: device, x: x, y: y, holdFor: hold)
				})

			case "swipe":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let from = try CGPoint(x: number(arguments, "from_x"), y: number(arguments, "from_y"))
				let to = try CGPoint(x: number(arguments, "to_x"), y: number(arguments, "to_y"))
				let duration = milliseconds(arguments, "duration_ms", default: 300, range: 50...5000)
				return text(try await performWaitingForSettle(
					"Swiped from (\(format(from.x)), \(format(from.y))) to (\(format(to.x)), \(format(to.y))).",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.swipe(device: device, from: from, to: to, duration: duration)
				})

			case "type_text":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let value = try string(arguments, "text")
				return text(try await performWaitingForSettle(
					"Typed \(value.count) characters.",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.type(device: device, text: value)
				})

			case "press_key":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let names = try keyNames(arguments)
				// All parsed before any is pressed, so a typo does not leave a sequence half done.
				let strokes = try names.map { name in
					guard let stroke = SimulatorKeyboardMap.keyStroke(named: name) else {
						throw SimulatorError.unknownKey(name)
					}
					return stroke
				}
				return text(try await performWaitingForSettle(
					"Pressed \(names.joined(separator: ", ")).",
					device: device,
					arguments: arguments,
					actions: actions
				) {
					try await actions.press(device: device, keys: strokes)
				})

			case "press_button":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let name = try string(arguments, "button")
				guard let button = SimulatorHardwareButton(rawValue: name) else {
					throw ToolError("Unknown button \"\(name)\".")
				}
				let hold = milliseconds(arguments, "duration_ms", default: 100, range: 20...10000)
				return text(try await performWaitingForSettle("Pressed \(name).", device: device, arguments: arguments, actions: actions) {
					try await actions.press(device: device, button: button, holdFor: hold)
				})

			case _ where SimulatorFeatureTools.names.contains(name):
				return text(try await SimulatorFeatureTools.call(name: name, arguments: arguments, actions: actions) {
					try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				})

			case _ where SimulatorElementTools.names.contains(name):
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				return text(try await SimulatorElementTools.call(name: name, arguments: arguments, device: device, actions: actions))

			case "list_crashes":
				let request = await SimulatorCrashReports.listRequest(arguments: arguments, actions: actions)
				return text(try await SimulatorCrashReports.list(request, source: actions.crashReports))

			case "crash_report":
				return text(try await SimulatorCrashReports.report(named: string(arguments, "name"), source: actions.crashReports))

			case "rotate":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let name = try string(arguments, "orientation")
				guard let orientation = SimulatorDeviceOrientation(rawValue: name) else {
					throw ToolError("Unknown orientation \"\(name)\".")
				}
				let rotated = try await actions.rotate(device: device, to: orientation)
				return text(rotationReport(rotated, orientation: orientation))

			case "set_fold":
				let device = try await device(for: arguments, actions: actions, reportActivity: reportActivity)
				let name = try string(arguments, "state")
				guard let fold = SimulatorFold(rawValue: name) else {
					throw ToolError("Unknown state \"\(name)\"; use open or closed.")
				}
				guard device.fold != nil else {
					throw SimulatorError.notFoldable(device.name)
				}
				let folded = try await actions.setFold(device: device, to: fold)
				let size = folded.screenPointSize
				let panel = fold == .open ? "the inner panel" : "the cover screen"
				return text("\(fold == .open ? "Unfolded" : "Folded") \(folded.name); it shows \(panel), \(Int(size.width))×\(Int(size.height)) points. Take a new screenshot before using coordinates.")

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
			let fold = device.fold.map { $0 == .open ? ", unfolded" : ", folded" } ?? ""
			return "\(device.name) (\(device.runtimeName)) \(device.id) — \(device.state.label), \(Int(size.width))×\(Int(size.height)) pt\(rotation)\(fold)\(shown)"
		}
		.joined(separator: "\n")
	}

	/// What a rotation did, including when the interface did not follow the device.
	private static func rotationReport(_ device: SimulatorDevice, orientation: SimulatorDeviceOrientation) -> String {
		let size = device.screenPointSize
		let points = "\(Int(size.width))×\(Int(size.height)) points"
		guard device.rotation == device.interfaceRotation(for: orientation) else {
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

	/// `keys`, or else `key` as a sequence of one.
	private static func keyNames(_ arguments: JSONValue) throws -> [String] {
		if case let .array(values)? = arguments["keys"] {
			let names = values.compactMap(\.stringValue)
			guard !names.isEmpty, names.count == values.count else {
				throw ToolError("\"keys\" must be a non-empty array of key names.")
			}
			return names
		}
		return [try string(arguments, "key")]
	}

	/// A boolean argument; models occasionally quote booleans, so "true" and "false" count too.
	static func flag(_ arguments: JSONValue, _ key: String, default value: Bool = false) -> Bool {
		switch arguments[key] {
		case let .bool(flag)?:
			flag
		case let .string(text)?:
			value ? text.lowercased() != "false" : text.lowercased() == "true"
		default:
			value
		}
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

	static let optionalUdid = udidProperty("Which simulator. Defaults to the one shown in Bridge Commander, or else a booted one.")

	static func udidProperty(_ description: String) -> JSONValue {
		["type": "string", "description": .string(description)]
	}

	static func number(_ description: String) -> JSONValue {
		["type": "number", "description": .string(description)]
	}

	static func tool(
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
