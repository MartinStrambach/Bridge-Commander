import CoreGraphics
import Foundation
import os
import Testing
@testable import SimulatorFeature

struct SimulatorMCPHandlerTests {
	private static let phone = SimulatorDevice(
		id: "AAAA",
		name: "iPhone",
		runtimeName: "iOS 27.0",
		state: .booted,
		screenPixelSize: CGSize(width: 1206, height: 2622),
		screenScale: 3
	)

	private final class FakeActions: SimulatorToolActions, @unchecked Sendable {
		let calls = OSAllocatedUnfairLock<[String]>(initialState: [])
		var devicesResult: [SimulatorDevice] = [phone]

		func devices() async throws -> [SimulatorDevice] { devicesResult }
		var selectedDeviceId: String? { "AAAA" }
		func resolveDevice(udid: String?) async throws -> SimulatorDevice {
			guard let device = devicesResult.first(where: \.isBooted) else {
				throw SimulatorError.noBootedDevice
			}
			return device
		}
		func select(_ device: SimulatorDevice) async { record("select \(device.id)") }
		func screenshotJPEG(device: SimulatorDevice) async throws -> Data { Data([0xFF, 0xD8]) }
		func tap(device: SimulatorDevice, x: Double, y: Double, holdFor: Duration) async throws {
			record("tap \(x) \(y) \(holdFor)")
		}
		func swipe(device: SimulatorDevice, from: CGPoint, to: CGPoint, duration: Duration) async throws {
			record("swipe \(from.x),\(from.y) \(to.x),\(to.y)")
		}
		func type(device: SimulatorDevice, text: String) async throws { record("type \(text)") }
		func press(device: SimulatorDevice, key: SimulatorKeyStroke) async throws { record("key \(key.usage)") }
		func press(device: SimulatorDevice, button: SimulatorHardwareButton) async throws { record("button \(button.rawValue)") }
		func accessibilityTree(device: SimulatorDevice) async throws -> SimulatorAccessibilityNode {
			SimulatorAccessibilityNode(
				role: "Application",
				label: "Demo",
				frame: CGRect(x: 0, y: 0, width: 402, height: 874),
				children: [SimulatorAccessibilityNode(role: "Button", label: "Go", frame: CGRect(x: 10, y: 20, width: 30, height: 40))]
			)
		}
		func accessibilityElement(device: SimulatorDevice, at point: CGPoint) async throws -> SimulatorAccessibilityNode? {
			point.x < 50 ? SimulatorAccessibilityNode(role: "Button", label: "Go", frame: CGRect(x: 10, y: 20, width: 30, height: 40)) : nil
		}
		func twoFingerGesture(device: SimulatorDevice, from: FingerPair, to: FingerPair, duration: Duration) async throws {
			record("two \(from.first.x),\(from.second.x) -> \(to.first.x),\(to.second.x)")
		}
		/// The interface follows every orientation but upside down, as on a Face ID iPhone.
		func rotate(device: SimulatorDevice, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorDevice {
			record("rotate \(orientation.rawValue)")
			var rotated = device
			rotated.rotation = orientation == .portraitUpsideDown ? device.rotation : orientation.screenRotation
			return rotated
		}

		private func record(_ call: String) {
			calls.withLock { $0.append(call) }
		}
	}

	private func post(_ body: JSONValue, headers: [String: String] = [:]) throws -> HTTPRequest {
		HTTPRequest(method: "POST", path: "/mcp", headers: headers, body: try JSONEncoder().encode(body))
	}

	private func decode(_ response: HTTPResponse) throws -> JSONValue {
		try JSONDecoder().decode(JSONValue.self, from: response.body)
	}

	private func handler(
		_ actions: FakeActions,
		activity: OSAllocatedUnfairLock<[SimulatorActivity]> = .init(initialState: [])
	) -> SimulatorMCPHandler {
		SimulatorMCPHandler(actions: actions) { reported in
			activity.withLock { $0.append(reported) }
		}
	}

	@Test
	func initializeEchoesASupportedVersion() async throws {
		let response = await handler(FakeActions()).response(to: try post([
			"jsonrpc": "2.0", "id": 1, "method": "initialize",
			"params": ["protocolVersion": "2025-06-18", "capabilities": [:]],
		]))
		let result = try decode(response)["result"]
		#expect(response.status == 200)
		#expect(result?["protocolVersion"] == "2025-06-18")
		#expect(result?["serverInfo"]?["name"] == "bridge-commander-simulator")
	}

	@Test
	func initializeOffersTheNewestVersionForAnUnknownOne() async throws {
		let response = await handler(FakeActions()).response(to: try post([
			"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "1999-01-01"],
		]))
		#expect(try decode(response)["result"]?["protocolVersion"] == .string(SimulatorMCPHandler.supportedProtocolVersions[0]))
	}

	@Test
	func notificationsGetAnEmptyAccepted() async throws {
		let response = await handler(FakeActions()).response(to: try post([
			"jsonrpc": "2.0", "method": "notifications/initialized",
		]))
		#expect(response.status == 202)
		#expect(response.body.isEmpty)
	}

	@Test
	func onlyPostToTheEndpointIsServed() async {
		let get = HTTPRequest(method: "GET", path: "/mcp", headers: [:], body: Data())
		#expect(await handler(FakeActions()).response(to: get).status == 405)
		let elsewhere = HTTPRequest(method: "POST", path: "/other", headers: [:], body: Data())
		#expect(await handler(FakeActions()).response(to: elsewhere).status == 404)
	}

	@Test
	func listsEveryTool() async throws {
		let response = await handler(FakeActions()).response(to: try post(["jsonrpc": "2.0", "id": "x", "method": "tools/list"]))
		guard case let .array(tools)? = try decode(response)["result"]?["tools"] else {
			Issue.record("expected a tool list")
			return
		}
		let names = tools.compactMap { $0["name"]?.stringValue }
		#expect(names == [
			"list_devices", "select_device", "screenshot", "describe_ui", "tap", "swipe", "pinch", "two_finger_drag",
			"type_text", "press_key", "press_button", "rotate",
		])
		#expect(try decode(response)["id"] == "x")
	}

	@Test
	func tapActsOnTheDeviceAndReportsTheCallingSession() async throws {
		let actions = FakeActions()
		let activity = OSAllocatedUnfairLock<[SimulatorActivity]>(initialState: [])
		let session = UUID()
		let response = await handler(actions, activity: activity).response(to: try post(
			[
				"jsonrpc": "2.0", "id": 2, "method": "tools/call",
				"params": ["name": "tap", "arguments": ["x": 100, "y": "200.5"]],
			],
			headers: ["x-bridge-commander-session": session.uuidString]
		))

		#expect(try decode(response)["result"]?["isError"] == false)
		#expect(actions.calls.withLock { $0 } == ["tap 100.0 200.5 0.06 seconds"])
		#expect(activity.withLock { $0 } == [SimulatorActivity(terminalSessionId: session, deviceId: "AAAA")])
	}

	@Test
	func screenshotReturnsAnImageAndItsSize() async throws {
		let response = await handler(FakeActions()).response(to: try post([
			"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "screenshot", "arguments": [:]],
		]))
		guard case let .array(content)? = try decode(response)["result"]?["content"] else {
			Issue.record("expected content")
			return
		}
		#expect(content.first?["type"] == "image")
		#expect(content.first?["mimeType"] == "image/jpeg")
		#expect(content.first?["data"] == .string(Data([0xFF, 0xD8]).base64EncodedString()))
		#expect(content.last?["text"] == "iPhone, 402×874 points.")
	}

	@Test
	func failuresComeBackAsToolErrors() async throws {
		let actions = FakeActions()
		actions.devicesResult = []
		let noDevice = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "tap", "arguments": ["x": 1, "y": 1]],
		]))
		#expect(try decode(noDevice)["result"]?["isError"] == true)

		let badKey = await handler(FakeActions()).response(to: try post([
			"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "press_key", "arguments": ["key": "warp"]],
		]))
		#expect(try decode(badKey)["result"]?["isError"] == true)
	}

	@Test
	func unknownMethodsAreJSONRPCErrors() async throws {
		let response = await handler(FakeActions()).response(to: try post(["jsonrpc": "2.0", "id": 6, "method": "resources/list"]))
		#expect(try decode(response)["error"]?["code"] == -32601)
	}

	@Test
	func malformedBodiesAreParseErrors() async {
		let request = HTTPRequest(method: "POST", path: "/mcp", headers: [:], body: Data("{nope".utf8))
		let response = await handler(FakeActions()).response(to: request)
		#expect(response.status == 400)
	}

	@Test
	func describeUIListsTheTreeOrTheElementAtAPoint() async throws {
		func call(_ arguments: JSONValue) async throws -> String? {
			let response = await handler(FakeActions()).response(to: try post([
				"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "describe_ui", "arguments": arguments],
			]))
			guard case let .array(content)? = try decode(response)["result"]?["content"] else {
				return nil
			}
			return content.first?["text"]?.stringValue
		}

		let tree = try await call([:])
		#expect(tree?.contains("  Button \"Go\" frame=(10,20,30,40)") == true)
		#expect(try await call(["x": 20, "y": 30]) == "Button \"Go\" frame=(10,20,30,40)")
		#expect(try await call(["x": 300, "y": 30]) == "No accessibility element at (300, 30).")
	}

	@Test
	func pinchAndTwoFingerDragDriveTwoFingers() async throws {
		let actions = FakeActions()
		_ = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": ["name": "pinch", "arguments": ["x": 200, "y": 400, "scale": 2]],
		]))
		_ = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 9, "method": "tools/call",
			"params": ["name": "two_finger_drag", "arguments": ["from_x": 100, "from_y": 500, "to_x": 100, "to_y": 300]],
		]))
		#expect(actions.calls.withLock { $0 } == ["two 170.0,230.0 -> 140.0,260.0", "two 80.0,120.0 -> 80.0,120.0"])
	}

	private func callText(_ actions: FakeActions, _ name: String, _ arguments: JSONValue) async throws -> (text: String?, isError: JSONValue?) {
		let response = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments],
		]))
		let result = try decode(response)["result"]
		guard case let .array(content)? = result?["content"] else {
			return (nil, result?["isError"])
		}
		return (content.last?["text"]?.stringValue, result?["isError"])
	}

	@Test
	func rotateReportsTheTurnedScreen() async throws {
		let actions = FakeActions()
		let turned = try await callText(actions, "rotate", ["orientation": "landscape_left"])
		#expect(turned.isError == false)
		#expect(turned.text == "Rotated to landscape left. The screen is now 874×402 points; take a new screenshot before using coordinates.")

		let refused = try await callText(actions, "rotate", ["orientation": "portrait_upside_down"])
		#expect(refused.text?.hasPrefix("Turned the device to portrait upside down, but the interface stayed portrait") == true)
		#expect(refused.text?.hasSuffix("The screen is 402×874 points.") == true)
		#expect(actions.calls.withLock { $0 } == ["rotate landscape_left", "rotate portrait_upside_down"])

		let unknown = try await callText(actions, "rotate", ["orientation": "sideways"])
		#expect(unknown.isError == true)
	}

	@Test
	func aRotatedDeviceIsListedAndShotInLandscape() async throws {
		let actions = FakeActions()
		var rotated = Self.phone
		rotated.rotation = .clockwise
		actions.devicesResult = [rotated]

		let list = try await callText(actions, "list_devices", [:])
		#expect(list.text == "iPhone (iOS 27.0) AAAA — Booted, 874×402 pt landscape [shown]")
		let shot = try await callText(actions, "screenshot", [:])
		#expect(shot.text == "iPhone, 874×402 points (landscape).")
	}
}
