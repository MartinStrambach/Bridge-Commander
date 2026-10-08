import CoreGraphics
import Foundation
import Network
import os

/// The local MCP server Claude Code connects to: HTTP on loopback, at
/// `http://127.0.0.1:<port>/mcp`.
///
/// HTTP rather than a stdio helper because the tools have to act on this process's state — the
/// pane on screen, the device selected in it — and an HTTP server is the one MCP transport an app
/// can host itself. Each terminal pane is started with `BC_SIMULATOR_MCP_URL` and
/// `BC_TERMINAL_SESSION_ID`, which the Claude Code registration expands into the server URL and a
/// header, so a call is known to come from a particular tab (`ClaudeCodeRegistration`).
public final class SimulatorMCPServer: @unchecked Sendable {
	public static let shared = SimulatorMCPServer()

	/// Release and debug builds run side by side, so each has its own port. The registration's
	/// fallback URL (used by a `claude` started outside the app's panes) is the release one.
	static let releasePort: UInt16 = 47615
	static let debugPort: UInt16 = 47616

	static var preferredPort: UInt16 {
		Bundle.main.bundleIdentifier?.hasSuffix(".debug") == true ? debugPort : releasePort
	}

	public static let urlEnvironmentVariable = "BC_SIMULATOR_MCP_URL"
	public static let sessionEnvironmentVariable = "BC_TERMINAL_SESSION_ID"

	private struct State {
		var listener: NWListener?
		var port: UInt16?
		var subscribers: [UUID: AsyncStream<SimulatorActivity>.Continuation] = [:]
		/// The repository each terminal session was started in, from `terminalEnvironment`, so a
		/// call from that session acts on the repository's own device. Never pruned: an entry is a
		/// few bytes, and a closed session's id never comes back.
		var sessionRepositories: [UUID: String] = [:]
	}

	private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())
	private let queue = DispatchQueue(label: "com.bridgecommander.simulator.mcp")
	private let logger = Logger(subsystem: "com.bridgecommander", category: "SimulatorMCP")

	private init() {}

	/// The URL a pane's `claude` should use. The preferred port until the listener says otherwise,
	/// so panes created before it is up still get the right address in the usual case.
	public var endpointURL: String {
		"http://127.0.0.1:\(state.withLock { $0.port } ?? Self.preferredPort)\(SimulatorMCPHandler.path)"
	}

	/// The variables a terminal pane is started with, `NAME=value`. Also notes the session's
	/// repository: every shell, restored tabs' included, is started through here.
	public func terminalEnvironment(sessionId: UUID, repositoryPath: String) -> [String] {
		startIfNeeded()
		state.withLock { $0.sessionRepositories[sessionId] = repositoryPath }
		return [
			"\(Self.urlEnvironmentVariable)=\(endpointURL)",
			"\(Self.sessionEnvironmentVariable)=\(sessionId.uuidString)",
		]
	}

	/// Calls that touched a device, for the pane to come up showing it.
	public func activity() -> AsyncStream<SimulatorActivity> {
		startIfNeeded()
		let (stream, continuation) = AsyncStream<SimulatorActivity>.makeStream(bufferingPolicy: .bufferingNewest(8))
		let id = UUID()
		state.withLock { $0.subscribers[id] = continuation }
		continuation.onTermination = { [weak self] _ in
			self?.state.withLock { $0.subscribers[id] = nil }
		}
		return stream
	}

	public func startIfNeeded() {
		let needsStart = state.withLock { state in
			guard state.listener == nil else {
				return false
			}
			// Claimed before the listener exists so concurrent callers start only one.
			state.port = Self.preferredPort
			return true
		}
		if needsStart {
			start(port: Self.preferredPort)
		}
	}

	private func start(port: UInt16) {
		do {
			let parameters = NWParameters.tcp
			parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
			parameters.allowLocalEndpointReuse = true
			let listener = try NWListener(using: parameters)
			listener.newConnectionHandler = { [weak self] connection in
				self?.accept(connection)
			}
			listener.stateUpdateHandler = { [weak self, weak listener] newState in
				guard let self, let listener else {
					return
				}
				switch newState {
				case .ready:
					let bound = listener.port?.rawValue ?? port
					self.state.withLock { $0.port = bound }
					self.logger.info("Simulator MCP server listening on 127.0.0.1:\(bound)")
				case let .failed(error):
					listener.cancel()
					self.logger.error("Simulator MCP listener on \(port) failed: \(error.localizedDescription)")
					// The preferred port is taken (another copy of the app, say): any free port
					// still serves the panes, which are told the actual URL.
					if port != 0 {
						self.start(port: 0)
					}
				default:
					break
				}
			}
			state.withLock { $0.listener = listener }
			listener.start(queue: queue)
		}
		catch {
			logger.error("Simulator MCP listener could not be created: \(error.localizedDescription)")
			if port != 0 {
				start(port: 0)
			}
		}
	}

	private func publish(_ activity: SimulatorActivity) {
		for continuation in state.withLock({ Array($0.subscribers.values) }) {
			continuation.yield(activity)
		}
	}

	// MARK: - Connections

	private func accept(_ connection: NWConnection) {
		let handler = SimulatorMCPHandler(
			actions: { [weak self] sessionId in
				let repositoryPath = sessionId.flatMap { id in self?.state.withLock { $0.sessionRepositories[id] } }
				return LiveSimulatorToolActions(repositoryPath: repositoryPath)
			},
			onActivity: { [weak self] activity in
				self?.publish(activity)
			}
		)
		let session = HTTPConnectionSession(connection: connection, handler: handler, port: { [weak self] in
			self?.state.withLock { $0.port } ?? Self.preferredPort
		})
		session.start(queue: queue)
	}
}

/// One client connection: reads requests one after another (HTTP/1.1 keep-alive) and answers each
/// before reading the next.
private final class HTTPConnectionSession: @unchecked Sendable {
	private let connection: NWConnection
	private let handler: SimulatorMCPHandler
	private let port: @Sendable () -> UInt16
	private var buffer = Data()

	init(connection: NWConnection, handler: SimulatorMCPHandler, port: @escaping @Sendable () -> UInt16) {
		self.connection = connection
		self.handler = handler
		self.port = port
	}

	func start(queue: DispatchQueue) {
		connection.stateUpdateHandler = { [connection] state in
			if case .failed = state {
				connection.cancel()
			}
		}
		connection.start(queue: queue)
		receive()
	}

	private func receive() {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, isComplete, error in
			if let data {
				buffer.append(data)
			}
			switch HTTPParser.parse(buffer) {
			case .incomplete:
				if isComplete || error != nil {
					connection.cancel()
				}
				else {
					receive()
				}
			case let .invalid(response):
				send(response, keepAlive: false)
			case let .request(request, consumed):
				buffer.removeFirst(consumed)
				respond(to: request)
			}
		}
	}

	private func respond(to request: HTTPRequest) {
		if let rejection = HTTPParser.rejection(for: request, port: port()) {
			send(rejection, keepAlive: false)
			return
		}
		let keepAlive = request.header("connection")?.lowercased() != "close"
		Task { [self] in
			let response = await handler.response(to: request)
			send(response, keepAlive: keepAlive)
		}
	}

	private func send(_ response: HTTPResponse, keepAlive: Bool) {
		connection.send(content: response.serialized(keepAlive: keepAlive), completion: .contentProcessed { [self] error in
			if keepAlive, error == nil {
				// A request already buffered behind this one is answered before reading more.
				if case .request = HTTPParser.parse(buffer) {
					receiveBuffered()
				}
				else {
					receive()
				}
			}
			else {
				connection.cancel()
			}
		})
	}

	private func receiveBuffered() {
		guard case let .request(request, consumed) = HTTPParser.parse(buffer) else {
			receive()
			return
		}
		buffer.removeFirst(consumed)
		respond(to: request)
	}
}

/// The tool actions against the real simulators, for a call from `repositoryPath`'s terminal (`nil`
/// for a `claude` outside the app): the device it uses by default is that repository's.
private struct LiveSimulatorToolActions: SimulatorToolActions {
	let repositoryPath: String?

	private var host: SimulatorHost {
		.shared
	}

	func devices() async throws -> [SimulatorDevice] {
		try host.devices()
	}

	var selectedDeviceId: String? {
		host.selectedDeviceId(repositoryPath: repositoryPath)
	}

	func resolveDevice(udid: String?) async throws -> SimulatorDevice {
		try host.resolveDevice(udid: udid, repositoryPath: repositoryPath)
	}

	var crashReports: any SimulatorCrashReportSource {
		DiagnosticReportsDirectory()
	}

	func select(_ device: SimulatorDevice) async {
		host.select(deviceId: device.id, repositoryPath: repositoryPath)
	}

	func screenshotJPEG(device: SimulatorDevice) async throws -> Data {
		try host.screenshotJPEG(device: device)
	}

	func tap(device: SimulatorDevice, x: Double, y: Double, holdFor: Duration) async throws {
		try await host.tap(device: device, x: x, y: y, holdFor: holdFor)
	}

	func swipe(device: SimulatorDevice, from: CGPoint, to: CGPoint, duration: Duration) async throws {
		try await host.swipe(device: device, from: from, to: to, duration: duration)
	}

	func type(device: SimulatorDevice, text: String) async throws {
		try await host.type(device: device, text: text)
	}

	func press(device: SimulatorDevice, keys: [SimulatorKeyStroke]) async throws {
		try await host.press(device: device, keys: keys)
	}

	func press(device: SimulatorDevice, button: SimulatorHardwareButton, holdFor duration: Duration) async throws {
		try await host.press(device: device, button: button, holdFor: duration)
	}

	func accessibilityTree(device: SimulatorDevice) async throws -> SimulatorAccessibilityNode {
		try await host.accessibilityTree(device: device)
	}

	func accessibilityElement(device: SimulatorDevice, at point: CGPoint) async throws -> SimulatorAccessibilityNode? {
		try await host.accessibilityElement(device: device, at: point)
	}

	func twoFingerGesture(device: SimulatorDevice, from: FingerPair, to: FingerPair, duration: Duration) async throws {
		try await host.twoFingerGesture(device: device, from: from, to: to, duration: duration)
	}

	func screenFingerprint(device: SimulatorDevice) async -> ScreenFingerprint? {
		host.screenFingerprint(device: device)
	}

	func waitForScreenToSettle(device: SimulatorDevice, baseline: ScreenFingerprint?) async -> ScreenSettleResult {
		await host.waitForScreenToSettle(device: device, baseline: baseline)
	}

	func elementAction(_ action: SimulatorElementAction, on query: SimulatorElementQuery, device: SimulatorDevice) async throws -> SimulatorElementOutcome {
		try await host.performElementAction(action, on: query, device: device)
	}

	func rotate(device: SimulatorDevice, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorDevice {
		try await host.rotate(device: device, to: orientation)
	}

	func setFold(device: SimulatorDevice, to fold: SimulatorFold) async throws -> SimulatorDevice {
		try await host.setFold(device: device, to: fold)
	}

	func simulateMemoryWarning(device: SimulatorDevice) async throws {
		try host.simulateMemoryWarning(udid: device.id)
	}

	func setLocation(device: SimulatorDevice, _ command: SimulatorLocationCommand) async throws {
		try await host.setLocation(udid: device.id, command)
	}

	func startRecording(device: SimulatorDevice, path: String?) async throws -> URL {
		let url = try SimulatorScreenRecorder.destination(
			requested: path,
			deviceName: device.name,
			date: .now,
			defaultFolder: SimulatorScreenshotFile.defaultFolder(),
			isDirectory: SimulatorScreenshotFile.isDirectory,
			exists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
		)
		return try await SimulatorScreenRecorder.shared.start(udid: device.id, deviceName: device.name, screenID: device.screenID, to: url)
	}

	func stopRecording(udid: String?) async throws -> SimulatorRecording {
		let recorder = SimulatorScreenRecorder.shared
		let recording = recorder.recordingDeviceIds
		// The recorder keys by `uuidString`, which is upper case; a model may pass it lower case.
		let given = udid.map { udid in recording.first { $0.caseInsensitiveCompare(udid) == .orderedSame } ?? udid.uppercased() }
		guard let target = given ?? (recording.count == 1 ? recording.first : nil) ?? selectedDeviceId else {
			throw SimulatorError.notRecording("No simulator")
		}
		let name = (try? host.devices().first { $0.id.caseInsensitiveCompare(target) == .orderedSame })?.name ?? target
		return try await recorder.stop(udid: target, deviceName: name)
	}
}
