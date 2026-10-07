import AppKit
import ComposableArchitecture
import Foundation

/// The simulator pane's dependency: devices, booting, buttons, and the MCP server's activity.
@DependencyClient
public struct SimulatorClient: Sendable {
	public var devices: @Sendable () async throws -> [SimulatorDevice]
	public var selectedDeviceId: @Sendable () -> String? = { nil }
	public var selectDevice: @Sendable (_ id: String) -> Void
	public var boot: @Sendable (_ id: String) async throws -> Void
	public var shutdown: @Sendable (_ id: String) async throws -> Void
	public var pressButton: @Sendable (_ id: String, _ button: SimulatorHardwareButton) async throws -> Void
	/// Turns the device a quarter clockwise or counterclockwise from where it is.
	public var rotate: @Sendable (_ id: String, _ clockwise: Bool) async throws -> Void
	/// Saves the device's screen as a PNG where Simulator.app would, and returns the file.
	public var saveScreenshot: @Sendable (_ device: SimulatorDevice) async throws -> URL
	public var revealInFinder: @Sendable (_ url: URL) async -> Void
	/// Connects to the device's input service ahead of the first click.
	public var prepareInput: @Sendable (_ id: String) async -> Void
	/// Tool calls that touched a device. Starts the MCP server if it is not running.
	public var activity: @Sendable () -> AsyncStream<SimulatorActivity> = { .finished }
	public var isClaudeCodeConnected: @Sendable () -> Bool = { false }
	public var connectClaudeCode: @Sendable () async throws -> Void
}

extension SimulatorClient: DependencyKey {
	public static let liveValue = SimulatorClient(
		devices: { try SimulatorHost.shared.devices() },
		selectedDeviceId: { SimulatorHost.shared.selectedDeviceId },
		selectDevice: { SimulatorHost.shared.selectedDeviceId = $0 },
		boot: { try await SimulatorHost.shared.boot(udid: $0) },
		shutdown: { try await SimulatorHost.shared.shutdown(udid: $0) },
		pressButton: { try await SimulatorHost.shared.press(udid: $0, button: $1) },
		rotate: { try await SimulatorHost.shared.rotate(udid: $0, clockwise: $1) },
		saveScreenshot: { try SimulatorScreenshotFile.save(device: $0) },
		revealInFinder: { url in
			await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
		},
		prepareInput: { await SimulatorHost.shared.prepareInput(udid: $0) },
		activity: { SimulatorMCPServer.shared.activity() },
		isClaudeCodeConnected: { ClaudeCodeRegistration.isRegistered() },
		connectClaudeCode: { try await ClaudeCodeRegistration.register() }
	)
}

extension SimulatorClient: TestDependencyKey {
	public static let testValue = SimulatorClient()
}
