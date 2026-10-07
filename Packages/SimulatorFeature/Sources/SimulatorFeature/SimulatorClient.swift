import AppKit
import ComposableArchitecture
import Foundation

/// The simulator pane's dependency: devices, booting, buttons, Simulator.app's features, screen
/// recording, and the MCP server's activity.
@DependencyClient
public struct SimulatorClient: Sendable {
	public var devices: @Sendable () async throws -> [SimulatorDevice]
	/// The device chosen for a repository's pane (`SimulatorHost.selectedDeviceId(repositoryPath:)`).
	public var selectedDeviceId: @Sendable (_ repositoryPath: String?) -> String? = { _ in nil }
	public var selectDevice: @Sendable (_ id: String, _ repositoryPath: String?) -> Void
	public var boot: @Sendable (_ id: String) async throws -> Void
	public var shutdown: @Sendable (_ id: String) async throws -> Void
	public var pressButton: @Sendable (_ id: String, _ button: SimulatorHardwareButton) async throws -> Void
	/// Turns the device a quarter clockwise or counterclockwise from where it is.
	public var rotate: @Sendable (_ id: String, _ clockwise: Bool) async throws -> Void
	/// Saves the device's screen as a PNG where Simulator.app would, and returns the file.
	public var saveScreenshot: @Sendable (_ device: SimulatorDevice) async throws -> URL
	public var revealInFinder: @Sendable (_ url: URL) async -> Void
	public var simulateMemoryWarning: @Sendable (_ id: String) async throws -> Void
	public var setLocation: @Sendable (_ id: String, _ command: SimulatorLocationCommand) async throws -> Void
	/// Starts recording the device's screen into the folder screenshots go to.
	public var startRecording: @Sendable (_ device: SimulatorDevice) async throws -> Void
	public var stopRecording: @Sendable (_ device: SimulatorDevice) async throws -> SimulatorRecording
	/// The devices being recorded, now and whenever that changes — Claude starts and stops
	/// recordings too.
	public var recordingDeviceIds: @Sendable () -> AsyncStream<Set<String>> = { .finished }
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
		selectedDeviceId: { SimulatorHost.shared.selectedDeviceId(repositoryPath: $0) },
		selectDevice: { SimulatorHost.shared.select(deviceId: $0, repositoryPath: $1) },
		boot: { try await SimulatorHost.shared.boot(udid: $0) },
		shutdown: { try await SimulatorHost.shared.shutdown(udid: $0) },
		pressButton: { try await SimulatorHost.shared.press(udid: $0, button: $1) },
		rotate: { try await SimulatorHost.shared.rotate(udid: $0, clockwise: $1) },
		saveScreenshot: { try SimulatorScreenshotFile.save(device: $0) },
		revealInFinder: { url in
			await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
		},
		simulateMemoryWarning: { try SimulatorHost.shared.simulateMemoryWarning(udid: $0) },
		setLocation: { try await SimulatorHost.shared.setLocation(udid: $0, $1) },
		startRecording: { device in
			let url = SimulatorScreenshotFile.unusedURL(
				in: SimulatorScreenshotFile.defaultFolder(),
				name: SimulatorScreenshotFile.recordingName(deviceName: device.name, date: .now),
				exists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
			)
			_ = try await SimulatorScreenRecorder.shared.start(udid: device.id, deviceName: device.name, to: url)
		},
		stopRecording: { try await SimulatorScreenRecorder.shared.stop(udid: $0.id, deviceName: $0.name) },
		recordingDeviceIds: { SimulatorScreenRecorder.shared.recordingDeviceIdChanges() },
		prepareInput: { await SimulatorHost.shared.prepareInput(udid: $0) },
		activity: { SimulatorMCPServer.shared.activity() },
		isClaudeCodeConnected: { ClaudeCodeRegistration.isRegistered() },
		connectClaudeCode: { try await ClaudeCodeRegistration.register() }
	)
}

extension SimulatorClient: TestDependencyKey {
	public static let testValue = SimulatorClient()
}
