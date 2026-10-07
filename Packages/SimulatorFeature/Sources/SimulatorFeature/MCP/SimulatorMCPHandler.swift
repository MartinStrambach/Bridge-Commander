import CoreGraphics
import Foundation

/// What the MCP tools do to a simulator. `SimulatorHost` in the app; a fake in tests.
protocol SimulatorToolActions: Sendable {
	func devices() async throws -> [SimulatorDevice]
	var selectedDeviceId: String? { get }
	func resolveDevice(udid: String?) async throws -> SimulatorDevice
	func select(_ device: SimulatorDevice) async
	func screenshotJPEG(device: SimulatorDevice) async throws -> Data
	func tap(device: SimulatorDevice, x: Double, y: Double, holdFor: Duration) async throws
	func swipe(device: SimulatorDevice, from: CGPoint, to: CGPoint, duration: Duration) async throws
	func type(device: SimulatorDevice, text: String) async throws
	func press(device: SimulatorDevice, key: SimulatorKeyStroke) async throws
	func press(device: SimulatorDevice, button: SimulatorHardwareButton) async throws
	func accessibilityTree(device: SimulatorDevice) async throws -> SimulatorAccessibilityNode
	func accessibilityElement(device: SimulatorDevice, at point: CGPoint) async throws -> SimulatorAccessibilityNode?
	func twoFingerGesture(device: SimulatorDevice, from: FingerPair, to: FingerPair, duration: Duration) async throws
	var crashReports: any SimulatorCrashReportSource { get }
}

/// A tool call touched a device: the pane should show it, beside the terminal the call came from.
public struct SimulatorActivity: Equatable, Sendable {
	/// The terminal session whose Claude made the call, when it ran in one of the app's panes.
	public let terminalSessionId: UUID?
	public let deviceId: String
}

/// The MCP endpoint: JSON-RPC over HTTP POST ("Streamable HTTP" without the optional SSE stream —
/// every response is a single JSON body, which the spec allows).
struct SimulatorMCPHandler: Sendable {
	static let path = "/mcp"
	static let serverName = "bridge-commander-simulator"
	/// Newest first. An `initialize` asking for one of these gets it back; anything else gets the
	/// first.
	static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
	/// The header the registration fills from `BC_TERMINAL_SESSION_ID`.
	static let sessionHeader = "x-bridge-commander-session"

	let actions: any SimulatorToolActions
	let onActivity: @Sendable (SimulatorActivity) -> Void

	func response(to request: HTTPRequest) async -> HTTPResponse {
		let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
		guard path == Self.path else {
			return .text(404, "Not found")
		}
		guard request.method == "POST" else {
			// No server-initiated stream (GET) and no session to end (DELETE).
			return HTTPResponse(status: 405, headers: [("Allow", "POST")])
		}

		guard let message = try? JSONDecoder().decode(JSONValue.self, from: request.body), case .object = message else {
			return .json(Self.encode(Self.error(id: .null, code: -32700, message: "Parse error")), status: 400)
		}
		// A notification (no id) — `notifications/initialized`, a cancellation — needs no answer.
		guard let id = message["id"], id != .null else {
			return HTTPResponse(status: 202)
		}

		let sessionId = request.header(Self.sessionHeader).flatMap { UUID(uuidString: $0) }
		let reply = await handle(method: message["method"]?.stringValue ?? "", params: message["params"], id: id, sessionId: sessionId)
		return .json(Self.encode(reply))
	}

	private func handle(method: String, params: JSONValue?, id: JSONValue, sessionId: UUID?) async -> JSONValue {
		switch method {
		case "initialize":
			let requested = params?["protocolVersion"]?.stringValue
			let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
				?? Self.supportedProtocolVersions[0]
			return Self.result(id: id, [
				"protocolVersion": .string(version),
				"capabilities": ["tools": ["listChanged": false]],
				"serverInfo": ["name": .string(Self.serverName), "title": "Bridge Commander Simulator", "version": "1.0"],
				"instructions": .string(Self.instructions),
			])
		case "ping":
			return Self.result(id: id, [:])
		case "tools/list":
			return Self.result(id: id, ["tools": .array(SimulatorMCPTools.definitions)])
		case "tools/call":
			let name = params?["name"]?.stringValue ?? ""
			let arguments = params?["arguments"] ?? [:]
			let result = await SimulatorMCPTools.call(name: name, arguments: arguments, actions: actions) { deviceId in
				onActivity(SimulatorActivity(terminalSessionId: sessionId, deviceId: deviceId))
			}
			return Self.result(id: id, result)
		default:
			return Self.error(id: id, code: -32601, message: "Method not found: \(method)")
		}
	}

	static let instructions = """
	Drives the iOS Simulator shown in Bridge Commander, beside the terminal you run in. Build and \
	install with xcodebuild and `xcrun simctl install`/`launch` as usual; use these tools to look \
	at the running app and interact with it. Coordinates are in points with the origin at the top \
	left — the same size as the screenshot image. describe_ui lists the screen's elements with \
	their frames: prefer it for finding what to tap, and screenshots for how things look. Check \
	the effect of an action afterwards; apps take a moment to respond, so if the screen has not \
	changed yet, look again.
	"""

	private static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
		["jsonrpc": "2.0", "id": id, "result": result]
	}

	private static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
		["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
	}

	private static func encode(_ value: JSONValue) -> Data {
		(try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
	}
}
