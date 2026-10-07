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
	/// The screen before an action, for `waitForScreenToSettle` to compare against.
	func screenFingerprint(device: SimulatorDevice) async -> ScreenFingerprint?
	func waitForScreenToSettle(device: SimulatorDevice, baseline: ScreenFingerprint?) async -> ScreenSettleResult
	func elementAction(_ action: SimulatorElementAction, on query: SimulatorElementQuery, device: SimulatorDevice) async throws -> SimulatorElementOutcome
	var crashReports: any SimulatorCrashReportSource { get }
	/// Turns the device and returns it as it then is, its `rotation` the interface's.
	func rotate(device: SimulatorDevice, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorDevice
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

	/// The actions for a call from a terminal session (`nil` from outside the app), whose default
	/// device is that session's repository's.
	let actions: @Sendable (_ sessionId: UUID?) -> any SimulatorToolActions
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
			let result = await SimulatorMCPTools.call(name: name, arguments: arguments, actions: actions(sessionId)) { deviceId in
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
	left — the same size as the screenshot image, and as displayed when rotate has turned the \
	interface to landscape. describe_ui lists the screen's elements with \
	their frames: prefer it for finding what to tap, and screenshots for how things look. To act \
	on an element describe_ui lists, press_element, set_value and scroll_to_element find it by \
	identifier or label, with no coordinates. The actions (tap, swipe, pinch, two_finger_drag, \
	type_text, press_key, press_button and the element tools) return once \
	the screen has stopped changing, up to 3 s, and say whether it settled, did not change or is \
	still changing — so look at the result right away instead of waiting or taking extra \
	screenshots to catch up. Only when it is still changing (loading, a long animation) may a \
	later look differ. When the app crashes or vanishes, list_crashes and crash_report give the \
	crash's reason and backtrace.
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
