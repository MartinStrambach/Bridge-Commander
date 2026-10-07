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
				children: [
					SimulatorAccessibilityNode(role: "Button", label: "Go", frame: CGRect(x: 10, y: 20, width: 30, height: 40)),
					SimulatorAccessibilityNode(role: "StaticText", label: "Welcome", frame: CGRect(x: 10, y: 80, width: 200, height: 20)),
					SimulatorAccessibilityNode(role: "TextField", identifier: "email", frame: CGRect(x: 10, y: 120, width: 300, height: 40)),
				]
			)
		}
		func accessibilityElement(device: SimulatorDevice, at point: CGPoint) async throws -> SimulatorAccessibilityNode? {
			point.x < 50 ? SimulatorAccessibilityNode(role: "Button", label: "Go", frame: CGRect(x: 10, y: 20, width: 30, height: 40)) : nil
		}
		func twoFingerGesture(device: SimulatorDevice, from: FingerPair, to: FingerPair, duration: Duration) async throws {
			record("two \(from.first.x),\(from.second.x) -> \(to.first.x),\(to.second.x)")
		}
		var crashReports: any SimulatorCrashReportSource { crashSource }
		let crashSource = SimulatorCrashReportsTests.source()

		static let baseline = ScreenFingerprint(columns: 1, rows: 1, cells: [7])
		func screenFingerprint(device: SimulatorDevice) async -> ScreenFingerprint? {
			record("fingerprint")
			return Self.baseline
		}
		func waitForScreenToSettle(device: SimulatorDevice, baseline: ScreenFingerprint?) async -> ScreenSettleResult {
			record(baseline == Self.baseline ? "settle from baseline" : "settle")
			return .settled(after: .milliseconds(640))
		}

		/// Matches against `accessibilityTree` as the live side does; the effect stands in for the
		/// simulator's: buttons take AXPress, other elements get a tap, text fields take values.
		func elementAction(_ action: SimulatorElementAction, on query: SimulatorElementQuery, device: SimulatorDevice) async throws -> SimulatorElementOutcome {
			let candidates = try await accessibilityTree(device: device).flattened()
			let element = candidates[try query.match(in: candidates, preferring: action.preferredRoles)]
			record("element \(action) \(element.label ?? element.identifier ?? "")")
			switch action {
			case .press:
				let effect: SimulatorElementOutcome.Effect = element.role == "Button" ? .pressed : .tappedCentre(CGPoint(x: element.frame.midX, y: element.frame.midY))
				return SimulatorElementOutcome(element: element, effect: effect)
			case let .setValue(value):
				guard element.role == "TextField" else {
					throw SimulatorElementError.notSettable(element: SimulatorAccessibilityFormatter.line(for: element))
				}
				return SimulatorElementOutcome(element: element, effect: .valueSet(readBack: value))
			case .scrollToVisible:
				return SimulatorElementOutcome(element: element, effect: .scrolled(to: element.frame.offsetBy(dx: 0, dy: -50)))
			}
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
			"type_text", "press_key", "press_button", "press_element", "set_value", "scroll_to_element", "list_crashes", "crash_report",
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

		let result = try decode(response)["result"]
		#expect(result?["isError"] == false)
		#expect(result?["content"] == [["type": "text", "text": "Tapped (100, 200.5). Screen settled after 640 ms."]])
		#expect(actions.calls.withLock { $0 } == ["fingerprint", "tap 100.0 200.5 0.06 seconds", "settle from baseline"])
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
		#expect(actions.calls.withLock { $0 }.filter { $0.hasPrefix("two") } == ["two 170.0,230.0 -> 140.0,260.0", "two 80.0,120.0 -> 80.0,120.0"])
	}

	@Test
	func everyActionWaitsForTheScreenToSettleUnlessToldNotTo() async throws {
		let calls: [(String, JSONValue)] = [
			("tap", ["x": 1, "y": 1]),
			("swipe", ["from_x": 1, "from_y": 1, "to_x": 2, "to_y": 2]),
			("pinch", ["x": 100, "y": 100, "scale": 2]),
			("two_finger_drag", ["from_x": 100, "from_y": 100, "to_x": 100, "to_y": 200]),
			("type_text", ["text": "hi"]),
			("press_key", ["key": "return"]),
			("press_button", ["button": "home"]),
			("press_element", ["label": "Go"]),
			("set_value", ["value": "x"]),
			("scroll_to_element", ["identifier": "email"]),
		]
		for (name, arguments) in calls {
			let waiting = FakeActions()
			let response = await handler(waiting).response(to: try post([
				"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments],
			]))
			let text = try decode(response)["result"]?["content"]?.firstText
			#expect(text?.hasSuffix(" Screen settled after 640 ms.") == true, "\(name): \(text ?? "nil")")
			#expect(waiting.calls.withLock { $0.first == "fingerprint" && $0.last == "settle from baseline" }, "\(name)")

			guard case var .object(noWait) = arguments else {
				continue
			}
			for value: JSONValue in [false, "false"] {
				noWait["wait_for_settle"] = value
				let immediate = FakeActions()
				let quick = await handler(immediate).response(to: try post([
					"jsonrpc": "2.0", "id": 11, "method": "tools/call", "params": ["name": .string(name), "arguments": .object(noWait)],
				]))
				#expect(try decode(quick)["result"]?["content"]?.firstText?.contains("Screen") == false, "\(name)")
				#expect(immediate.calls.withLock { $0.count } == 1, "\(name)")
			}
		}
	}

	@Test
	func actionToolsOfferWaitForSettle() async throws {
		let response = await handler(FakeActions()).response(to: try post(["jsonrpc": "2.0", "id": "x", "method": "tools/list"]))
		guard case let .array(tools)? = try decode(response)["result"]?["tools"] else {
			Issue.record("expected a tool list")
			return
		}
		let offering = tools.filter { $0["inputSchema"]?["properties"]?["wait_for_settle"]?["type"] == "boolean" }
		#expect(offering.compactMap { $0["name"]?.stringValue } == [
			"tap", "swipe", "pinch", "two_finger_drag", "type_text", "press_key", "press_button",
			"press_element", "set_value", "scroll_to_element",
		])
	}

	private func callText(_ actions: FakeActions, _ name: String, _ arguments: JSONValue) async throws -> (text: String?, isError: Bool) {
		let response = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments],
		]))
		let result = try decode(response)["result"]
		guard case let .array(content)? = result?["content"] else {
			return (nil, true)
		}
		return (content.first?["text"]?.stringValue, result?["isError"] == true)
	}

	@Test
	func pressElementPressesOrTapsWhatItFinds() async throws {
		let actions = FakeActions()
		let pressed = try await callText(actions, "press_element", ["label": "go"])
		#expect(pressed.text == "Pressed Button \"Go\" frame=(10,20,30,40) (AXPress). Screen settled after 640 ms.")
		#expect(pressed.isError == false)

		let tapped = try await callText(actions, "press_element", ["label": "Welcome"])
		#expect(tapped.text == "Tapped the centre of StaticText \"Welcome\" frame=(10,80,200,20) at (110, 90): it has no accessibility press, or refused it. Screen settled after 640 ms.")
		#expect(actions.calls.withLock { $0 }.filter { $0.hasPrefix("element") } == ["element press Go", "element press Welcome"])
	}

	@Test
	func pressElementReportsMissesAndNeedsSomethingToGoOn() async throws {
		let missing = try await callText(FakeActions(), "press_element", ["identifier": "nope"])
		#expect(missing.isError)
		#expect(missing.text?.hasPrefix("No element matches identifier \"nope\". Elements on screen:\nButton \"Go\"") == true)

		let nothing = try await callText(FakeActions(), "press_element", [:])
		#expect(nothing.isError)
		#expect(nothing.text == SimulatorElementError.noCriteria.localizedDescription)
	}

	@Test
	func setValueFillsTheOnlyFieldOrRefuses() async throws {
		let actions = FakeActions()
		let set = try await callText(actions, "set_value", ["value": "me@example.com"])
		#expect(set.text == "Set the value of TextField id=email frame=(10,120,300,40); it now reads \"me@example.com\". Screen settled after 640 ms.")
		#expect(actions.calls.withLock { $0 } == ["fingerprint", "element setValue(\"me@example.com\") email", "settle from baseline"])

		let refused = try await callText(actions, "set_value", ["label": "Go", "value": "x"])
		#expect(refused.isError)
		#expect(refused.text?.contains("Tap it and use type_text instead") == true)

		let noValue = try await callText(actions, "set_value", ["identifier": "email"])
		#expect(noValue.isError)
		#expect(noValue.text == "Missing \"value\".")
	}

	@Test
	func scrollToElementReportsTheNewFrame() async throws {
		let scrolled = try await callText(FakeActions(), "scroll_to_element", ["identifier": "email", "index": 0, "wait_for_settle": false])
		#expect(scrolled.text == "Scrolled TextField id=email frame=(10,120,300,40) into view; its frame is now (10,70,300,40).")
	}

	@Test
	func crashToolsListAndSummariseReports() async throws {
		func call(_ name: String, _ arguments: JSONValue) async throws -> JSONValue? {
			let response = await handler(FakeActions()).response(to: try post([
				"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments],
			]))
			return try decode(response)["result"]
		}

		let list = try await call("list_crashes", ["udid": .string(CrashFixtures.udid), "since_minutes": 100_000])
		guard case let .array(listContent)? = list?["content"] else {
			Issue.record("expected content")
			return
		}
		#expect(list?["isError"] == false)
		#expect(listContent.first?["text"]?.stringValue?.contains("CrashDemo-2026-10-07-193128.ips") == true)

		let report = try await call("crash_report", ["name": "CrashDemo-2026-10-07-193214.ips"])
		guard case let .array(reportContent)? = report?["content"] else {
			Issue.record("expected content")
			return
		}
		#expect(reportContent.first?["text"]?.stringValue?.contains("0  CrashDemo  crash(_:) + 780 (main.swift:31)") == true)

		#expect(try await call("crash_report", ["name": "../../.ssh/id_rsa"])?["isError"] == true)
	}
}

private extension JSONValue {
	/// The text of a tool result's first content block.
	var firstText: String? {
		guard case let .array(blocks) = self else {
			return nil
		}
		return blocks.first?["text"]?.stringValue
	}
}
