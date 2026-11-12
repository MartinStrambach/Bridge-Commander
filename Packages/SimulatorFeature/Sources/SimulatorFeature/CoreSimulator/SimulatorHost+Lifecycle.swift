import Foundation
import ProcessExecution

extension SimulatorHost {
	/// Boots a device headless, the way `xcrun simctl boot` does — no Simulator.app window. The
	/// pane is the window.
	public func boot(udid: String) async throws {
		try await simctl(["boot", udid])
	}

	public func shutdown(udid: String) async throws {
		try await simctl(["shutdown", udid])
	}

	/// Erases all content and settings, as Device ▸ Erase All Content and Settings does. simctl
	/// erases only a shut-down device, so a booted one is shut down first and booted again after.
	/// Returns whether it was booted again.
	public func erase(udid: String) async throws -> Bool {
		guard let device = try devices().first(where: { $0.id == udid }) else {
			throw SimulatorError.deviceNotFound(udid)
		}
		let wasRunning = device.state == .booted || device.state == .booting
		if wasRunning {
			try await shutdown(udid: udid)
		}
		try await simctl(["erase", udid])
		if wasRunning {
			try await boot(udid: udid)
		}
		return wasRunning
	}

	/// Runs `xcrun simctl` with `arguments` and returns what it printed; a failure throws what it
	/// printed to stderr. `extraEnvironment` goes on top of the usual environment (`SIMCTL_CHILD_`
	/// variables for an app being launched).
	@discardableResult
	func simctl(_ arguments: [String], extraEnvironment: [String: String] = [:]) async throws -> String {
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: ["simctl"] + arguments,
			environment: EnvironmentHelper.setupEnvironment().merging(extraEnvironment) { $1 }
		)
		guard result.success else {
			let message = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw SimulatorError.commandFailed(message.isEmpty ? "simctl \(arguments.joined(separator: " ")) failed" : message)
		}
		return result.outputString
	}
}
