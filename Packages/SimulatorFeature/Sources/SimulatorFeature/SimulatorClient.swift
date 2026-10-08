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
	/// Opens or closes a device that folds (the iPhone Duo).
	public var setFold: @Sendable (_ device: SimulatorDevice, _ fold: SimulatorFold) async throws -> Void
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
	/// The schemes of a workspace or project that launch an app (`XcodeSchemeScanner`).
	public var runnableSchemes: @Sendable (_ projectPath: String) async -> [XcodeScheme] = { _ in [] }
	/// The scheme last run for a workspace or project, by its file name, so every worktree of a
	/// repository starts on the same one.
	public var storedSchemeName: @Sendable (_ projectFileName: String) -> String? = { _ in nil }
	public var storeSchemeName: @Sendable (_ name: String, _ projectFileName: String) -> Void
	/// Writes the run script and returns the command that builds and launches `scheme` on `device`.
	public var runCommand: @Sendable (_ projectPath: String, _ scheme: XcodeScheme, _ device: SimulatorDevice) throws -> String
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
		setFold: { _ = try await SimulatorHost.shared.setFold(device: $0, to: $1) },
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
			_ = try await SimulatorScreenRecorder.shared.start(udid: device.id, deviceName: device.name, screenID: device.screenID, to: url)
		},
		stopRecording: { try await SimulatorScreenRecorder.shared.stop(udid: $0.id, deviceName: $0.name) },
		recordingDeviceIds: { SimulatorScreenRecorder.shared.recordingDeviceIdChanges() },
		prepareInput: { await SimulatorHost.shared.prepareInput(udid: $0) },
		activity: { SimulatorMCPServer.shared.activity() },
		isClaudeCodeConnected: { ClaudeCodeRegistration.isRegistered() },
		connectClaudeCode: { try await ClaudeCodeRegistration.register() },
		runnableSchemes: { path in await XcodeSchemeScanner.schemes(in: path) },
		storedSchemeName: { UserDefaults.standard.dictionary(forKey: runSchemesKey)?[$0] as? String },
		storeSchemeName: { name, projectFileName in
			var schemes = UserDefaults.standard.dictionary(forKey: runSchemesKey) ?? [:]
			schemes[projectFileName] = name
			UserDefaults.standard.set(schemes, forKey: runSchemesKey)
		},
		runCommand: { projectPath, scheme, device in
			try SimulatorRunCommand.prepare(
				in: SimulatorRunCommand.defaultFolder(),
				projectPath: projectPath,
				scheme: scheme,
				device: device
			)
		}
	)

	private static let runSchemesKey = "simulatorRunSchemeByProject"
}

extension SimulatorClient: TestDependencyKey {
	public static let testValue = SimulatorClient()
}
