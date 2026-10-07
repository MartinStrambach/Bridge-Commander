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

	/// Runs `xcrun simctl` with `arguments`; a failure throws what it printed to stderr.
	func simctl(_ arguments: [String]) async throws {
		let result = await ProcessRunner.run(
			executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: ["simctl"] + arguments,
			environment: EnvironmentHelper.setupEnvironment()
		)
		guard result.success else {
			let message = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
			throw SimulatorError.commandFailed(message.isEmpty ? "simctl \(arguments.joined(separator: " ")) failed" : message)
		}
	}
}
