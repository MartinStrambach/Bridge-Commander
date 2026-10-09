import Foundation

/// `set_appearance`, `set_status_bar` and `erase_device` — the device's settings, which `simctl`
/// changes without going through the Settings app.
nonisolated enum SimulatorDeviceTools {
	static let names: Set<String> = ["set_appearance", "set_status_bar", "erase_device"]

	static var definitions: [JSONValue] {
		[
			SimulatorMCPTools.tool(
				"set_appearance",
				"Set the simulator's light or dark mode, text size (Dynamic Type) and Increase Contrast — any of them in one call. Apps follow at once, as when changed in Settings; check how a screen looks in dark mode or at the largest text sizes.",
				properties: [
					"appearance": choices(SimulatorAppearance.allCases.map(\.rawValue), "Light or dark mode."),
					"content_size": choices(
						SimulatorUISettings.contentSizes + ["increment", "decrement"],
						"The preferred text size; the accessibility- sizes are Larger Accessibility Sizes. increment and decrement step from the current one."
					),
					"increase_contrast": ["type": "boolean", "description": "Turn Increase Contrast on or off."],
					"udid": SimulatorMCPTools.optionalUdid,
				]
			),
			SimulatorMCPTools.tool(
				"set_status_bar",
				"Override what the status bar shows — the time, signal, carrier and battery — for clean screenshots and recordings, or clear the override. clean sets Apple's marketing status bar (9:41, full Wi-Fi and cellular bars, no carrier, a full battery); fields given with it change that. The override lasts across reboots until cleared or the device is erased.",
				properties: [
					"clean": ["type": "boolean", "description": "Start from 9:41, full bars, no carrier and a full battery."],
					"clear": ["type": "boolean", "description": "Remove every override; the status bar shows the real values again."],
					"time": ["type": "string", "description": "The time shown, e.g. \"9:41\"; an ISO 8601 date also sets the date where one is shown."],
					"data_network": choices(SimulatorStatusBarOverride.dataNetworks, "The data network icon; hide hides it."),
					"wifi_mode": choices(SimulatorStatusBarOverride.wifiModes, "Wi-Fi state."),
					"wifi_bars": SimulatorMCPTools.number("Wi-Fi bars, 0–3."),
					"cellular_mode": choices(SimulatorStatusBarOverride.cellularModes, "Cellular state."),
					"cellular_bars": SimulatorMCPTools.number("Cellular bars, 0–4."),
					"operator_name": ["type": "string", "description": "The carrier name; \"\" for none."],
					"battery_state": choices(SimulatorStatusBarOverride.batteryStates, "Battery state."),
					"battery_level": SimulatorMCPTools.number("Battery percentage, 0–100."),
					"udid": SimulatorMCPTools.optionalUdid,
				]
			),
			SimulatorMCPTools.tool(
				"erase_device",
				"Erase all content and settings of a simulator — every installed app and its data, keychain, permissions, settings and status bar overrides — leaving it as new. A booted simulator is shut down, erased and booted again, which takes a while. It cannot be undone, so it needs the simulator's udid (list_devices).",
				properties: ["udid": SimulatorMCPTools.udidProperty("The simulator to erase. It need not be booted.")],
				required: ["udid"]
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
		case "set_appearance":
			let settings = try uiSettings(from: arguments)
			let device = try await device()
			try await actions.setUISettings(device: device, settings)
			return "Set \(device.name) to \(describe(settings))."

		case "set_status_bar":
			let command = try statusBarCommand(from: arguments)
			let device = try await device()
			try await actions.setStatusBar(device: device, command)
			return switch command {
			case .clear:
				"Cleared \(device.name)'s status bar override."
			case .override:
				"Overrode \(device.name)'s status bar. set_status_bar with clear removes the override."
			}

		default:
			guard let udid = arguments["udid"]?.stringValue else {
				throw SimulatorError.invalidArgument("Give the udid of the simulator to erase (list_devices shows them).")
			}
			guard let target = try await actions.devices().first(where: { $0.id.caseInsensitiveCompare(udid) == .orderedSame }) else {
				throw SimulatorError.deviceNotFound(udid)
			}
			let rebooted = try await actions.erase(device: target)
			return rebooted
				? "Erased \(target.name) and booted it again; it is as new, with no apps of yours installed."
				: "Erased \(target.name); it is as new, and still shut down."
		}
	}

	static func uiSettings(from arguments: JSONValue) throws(SimulatorError) -> SimulatorUISettings {
		var settings = SimulatorUISettings()
		if let name = arguments["appearance"]?.stringValue {
			guard let appearance = SimulatorAppearance(rawValue: name) else {
				throw .invalidArgument("\"appearance\" must be light or dark; got \"\(name)\".")
			}
			settings.appearance = appearance
		}
		settings.contentSize = arguments["content_size"]?.stringValue
		if arguments["increase_contrast"] != nil {
			settings.increaseContrast = SimulatorMCPTools.flag(arguments, "increase_contrast")
		}
		return settings
	}

	static func statusBarCommand(from arguments: JSONValue) throws(SimulatorError) -> SimulatorStatusBarCommand {
		let fields = ["time", "data_network", "wifi_mode", "wifi_bars", "cellular_mode", "cellular_bars", "operator_name", "battery_state", "battery_level"]
		let hasFields = fields.contains { arguments[$0] != nil }
		if SimulatorMCPTools.flag(arguments, "clear") {
			guard !hasFields, !SimulatorMCPTools.flag(arguments, "clean") else {
				throw .invalidArgument("Give clear alone; it removes every override.")
			}
			return .clear
		}
		var values = SimulatorMCPTools.flag(arguments, "clean") ? SimulatorStatusBarOverride.clean : SimulatorStatusBarOverride()
		func integer(_ key: String) throws(SimulatorError) -> Int? {
			guard let value = arguments[key] else {
				return nil
			}
			guard let number = value.doubleValue, number.rounded() == number else {
				throw .invalidArgument("\"\(key)\" must be a whole number.")
			}
			return Int(number)
		}
		if let time = arguments["time"]?.stringValue {
			values.time = time
		}
		if let network = arguments["data_network"]?.stringValue {
			values.dataNetwork = network
		}
		if let mode = arguments["wifi_mode"]?.stringValue {
			values.wifiMode = mode
		}
		if let bars = try integer("wifi_bars") {
			values.wifiBars = bars
		}
		if let mode = arguments["cellular_mode"]?.stringValue {
			values.cellularMode = mode
		}
		if let bars = try integer("cellular_bars") {
			values.cellularBars = bars
		}
		if let name = arguments["operator_name"]?.stringValue {
			values.operatorName = name
		}
		if let state = arguments["battery_state"]?.stringValue {
			values.batteryState = state
		}
		if let level = try integer("battery_level") {
			values.batteryLevel = level
		}
		return .override(values)
	}

	private static func describe(_ settings: SimulatorUISettings) -> String {
		var parts: [String] = []
		if let appearance = settings.appearance {
			parts.append("\(appearance.rawValue) mode")
		}
		if let size = settings.contentSize {
			parts.append(size == "increment" || size == "decrement" ? "the text size one step \(size == "increment" ? "larger" : "smaller")" : "text size \(size)")
		}
		if let contrast = settings.increaseContrast {
			parts.append("Increase Contrast \(contrast ? "on" : "off")")
		}
		return parts.joined(separator: ", ")
	}

	private static func choices(_ values: [String], _ description: String) -> JSONValue {
		["type": "string", "enum": .array(values.map { .string($0) }), "description": .string(description)]
	}
}
