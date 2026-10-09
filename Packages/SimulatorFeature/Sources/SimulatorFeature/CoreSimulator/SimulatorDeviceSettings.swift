import Foundation

/// Light or dark mode.
public enum SimulatorAppearance: String, CaseIterable, Sendable {
	case light
	case dark

	public var title: String {
		switch self {
		case .light:
			"Light"
		case .dark:
			"Dark"
		}
	}
}

/// What `simctl ui` sets: dark mode, the text size (Dynamic Type) and Increase Contrast. `nil`
/// leaves a setting as it is.
public struct SimulatorUISettings: Equatable, Sendable {
	public var appearance: SimulatorAppearance?
	/// A content size category as simctl names it (`contentSizes`), or "increment" / "decrement".
	public var contentSize: String?
	public var increaseContrast: Bool?

	public init(appearance: SimulatorAppearance? = nil, contentSize: String? = nil, increaseContrast: Bool? = nil) {
		self.appearance = appearance
		self.contentSize = contentSize
		self.increaseContrast = increaseContrast
	}

	/// The categories `simctl ui <udid> content_size` takes, smallest first.
	public static let contentSizes = [
		"extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large",
		"accessibility-medium", "accessibility-large", "accessibility-extra-large",
		"accessibility-extra-extra-large", "accessibility-extra-extra-extra-large",
	]

	/// One `simctl` call per setting given — `simctl ui` takes one option at a time.
	func simctlCommands(udid: String) throws(SimulatorError) -> [[String]] {
		var commands: [[String]] = []
		if let appearance {
			commands.append(["ui", udid, "appearance", appearance.rawValue])
		}
		if let contentSize {
			guard Self.contentSizes.contains(contentSize) || contentSize == "increment" || contentSize == "decrement" else {
				throw .invalidArgument("Unknown content size \"\(contentSize)\"; use one of \(Self.contentSizes.joined(separator: ", ")), increment or decrement.")
			}
			commands.append(["ui", udid, "content_size", contentSize])
		}
		if let increaseContrast {
			commands.append(["ui", udid, "increase_contrast", increaseContrast ? "enabled" : "disabled"])
		}
		guard !commands.isEmpty else {
			throw .invalidArgument("Give appearance, content_size or increase_contrast.")
		}
		return commands
	}
}

/// Fixed values for the status bar, as `simctl status_bar <udid> override` takes them. `nil`
/// leaves a field as the device shows it.
public struct SimulatorStatusBarOverride: Equatable, Sendable {
	/// A time ("9:41"), or an ISO 8601 date, which also sets the date where the status bar shows one.
	public var time: String?
	public var dataNetwork: String?
	public var wifiMode: String?
	public var wifiBars: Int?
	public var cellularMode: String?
	public var cellularBars: Int?
	/// "" hides the carrier name.
	public var operatorName: String?
	public var batteryState: String?
	public var batteryLevel: Int?

	public init(
		time: String? = nil,
		dataNetwork: String? = nil,
		wifiMode: String? = nil,
		wifiBars: Int? = nil,
		cellularMode: String? = nil,
		cellularBars: Int? = nil,
		operatorName: String? = nil,
		batteryState: String? = nil,
		batteryLevel: Int? = nil
	) {
		self.time = time
		self.dataNetwork = dataNetwork
		self.wifiMode = wifiMode
		self.wifiBars = wifiBars
		self.cellularMode = cellularMode
		self.cellularBars = cellularBars
		self.operatorName = operatorName
		self.batteryState = batteryState
		self.batteryLevel = batteryLevel
	}

	/// Apple's marketing status bar: 9:41, full signal, no carrier, a full battery.
	public static let clean = SimulatorStatusBarOverride(
		time: "9:41",
		dataNetwork: "wifi",
		wifiMode: "active",
		wifiBars: 3,
		cellularMode: "active",
		cellularBars: 4,
		operatorName: "",
		batteryState: "charged",
		batteryLevel: 100
	)

	static let dataNetworks = ["hide", "wifi", "3g", "4g", "lte", "lte-a", "lte+", "5g", "5g+", "5g-uwb", "5g-uc"]
	static let wifiModes = ["searching", "failed", "active"]
	static let cellularModes = ["notSupported", "searching", "failed", "active"]
	static let batteryStates = ["charging", "charged", "discharging"]

	/// The flags, checked here so a mistake names the argument the model gave rather than
	/// simctl's flag.
	func simctlFlags() throws(SimulatorError) -> [String] {
		func choice(_ value: String?, _ flag: String, _ name: String, _ allowed: [String]) throws(SimulatorError) -> [String] {
			guard let value else {
				return []
			}
			guard allowed.contains(value) else {
				throw .invalidArgument("\"\(name)\" must be one of \(allowed.joined(separator: ", ")); got \"\(value)\".")
			}
			return [flag, value]
		}
		func count(_ value: Int?, _ flag: String, _ name: String, _ range: ClosedRange<Int>) throws(SimulatorError) -> [String] {
			guard let value else {
				return []
			}
			guard range.contains(value) else {
				throw .invalidArgument("\"\(name)\" must be \(range.lowerBound)–\(range.upperBound); got \(value).")
			}
			return [flag, String(value)]
		}

		let flags = (time.map { ["--time", $0] } ?? [])
			+ (try choice(dataNetwork, "--dataNetwork", "data_network", Self.dataNetworks))
			+ (try choice(wifiMode, "--wifiMode", "wifi_mode", Self.wifiModes))
			+ (try count(wifiBars, "--wifiBars", "wifi_bars", 0...3))
			+ (try choice(cellularMode, "--cellularMode", "cellular_mode", Self.cellularModes))
			+ (try count(cellularBars, "--cellularBars", "cellular_bars", 0...4))
			+ (operatorName.map { ["--operatorName", $0] } ?? [])
			+ (try choice(batteryState, "--batteryState", "battery_state", Self.batteryStates))
			+ (try count(batteryLevel, "--batteryLevel", "battery_level", 0...100))
		guard !flags.isEmpty else {
			throw .invalidArgument("Give at least one status bar value, or clean, or clear.")
		}
		return flags
	}
}

/// What to do with the status bar — `simctl status_bar`'s actions.
public enum SimulatorStatusBarCommand: Equatable, Sendable {
	case override(SimulatorStatusBarOverride)
	/// Back to what the device really shows.
	case clear

	func simctlArguments(udid: String) throws(SimulatorError) -> [String] {
		switch self {
		case let .override(values):
			try ["status_bar", udid, "override"] + values.simctlFlags()
		case .clear:
			["status_bar", udid, "clear"]
		}
	}
}
