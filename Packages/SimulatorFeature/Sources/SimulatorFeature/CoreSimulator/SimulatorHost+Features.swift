import Foundation

/// Simulator.app's Features menu — memory warnings, the simulated location — and the settings
/// `simctl` changes without opening the Settings app: appearance, text size, the status bar.
extension SimulatorHost {
	/// `-[SimDevice simulateMemoryWarning]`, as Simulator.app's Debug ▸ Simulate Memory Warning and
	/// idb do: every app in the device gets `didReceiveMemoryWarning`. `void`, so it is sent with
	/// `ObjCRuntime.send`.
	public func simulateMemoryWarning(udid: String) throws {
		let device = try simDevice(udid: udid)
		guard ObjCRuntime.responds(device, to: "simulateMemoryWarning") else {
			throw SimulatorError.memoryWarningUnavailable
		}
		ObjCRuntime.send(device, "simulateMemoryWarning")
	}

	/// Through `simctl location` rather than `SimDevice`'s `SimLocation` methods: routes take
	/// waypoints in a shape the private API does not document, and simctl validates and encodes
	/// them. A process launch is cheap next to how rarely the location changes.
	public func setLocation(udid: String, _ command: SimulatorLocationCommand) async throws {
		try await simctl(command.simctlArguments(udid: udid))
	}

	/// `simctl ui`, one call per setting.
	public func setUISettings(udid: String, _ settings: SimulatorUISettings) async throws {
		for arguments in try settings.simctlCommands(udid: udid) {
			try await simctl(arguments)
		}
	}

	/// `simctl status_bar`. An override lasts until cleared or the device is erased, across reboots.
	public func setStatusBar(udid: String, _ command: SimulatorStatusBarCommand) async throws {
		try await simctl(command.simctlArguments(udid: udid))
	}

	/// `simctl openurl`: a web page opens in Safari, a custom scheme or universal link in its app.
	public func openURL(udid: String, _ url: String) async throws {
		guard let parsed = URL(string: url), let scheme = parsed.scheme, !scheme.isEmpty else {
			throw SimulatorError.invalidArgument("\"\(url)\" is not a URL with a scheme (https://…, myapp://…).")
		}
		try await simctl(["openurl", udid, url])
	}
}
