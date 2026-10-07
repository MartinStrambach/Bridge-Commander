import Foundation

/// Simulator.app's Features menu: memory warnings and the simulated location.
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
}
