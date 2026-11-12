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

		/// A slider whose row is wider than its track, as Settings' Dynamic Type slider is: the thumb
		/// runs from x 70 to 332 of a row from 20 to 382, and follows a drag only when the finger
		/// starts on it. `step` makes it move in steps, as that one does.
		struct Slider {
			var value = 0.5
			var step: Double?
			static let frame = CGRect(x: 20, y: 700, width: 362, height: 80)
			static let thumbMinX = 70.0
			static let trackWidth = 262.0

			mutating func set(_ value: Double) {
				let clamped = min(max(value, 0), 1)
				self.value = step.map { ($0 * (clamped / $0).rounded()) } ?? clamped
			}
		}
		let slider = OSAllocatedUnfairLock(initialState: Slider())
		/// How many tree reads the "Loaded" button waits before it appears; `nil` never shows it.
		let loadedAfterReads = OSAllocatedUnfairLock<Int?>(initialState: nil)

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
		func swipe(device: SimulatorDevice, from: CGPoint, to: CGPoint, duration: Duration, holdFor: Duration) async throws {
			record("swipe \(from.x),\(from.y) \(to.x),\(to.y)" + (holdFor > .zero ? " hold \(holdFor)" : ""))
			slider.withLock { slider in
				let thumbX = Slider.thumbMinX + slider.value * Slider.trackWidth
				guard Slider.frame.contains(from), abs(from.x - thumbX) <= 22 else {
					return
				}
				slider.set(slider.value + (to.x - from.x) / Slider.trackWidth)
			}
		}
		func type(device: SimulatorDevice, text: String) async throws { record("type \(text)") }
		func press(device: SimulatorDevice, keys: [SimulatorKeyStroke]) async throws {
			record("keys \(keys.map { String($0.usage) }.joined(separator: ","))")
		}
		func press(device: SimulatorDevice, button: SimulatorHardwareButton, holdFor: Duration) async throws {
			record("button \(button.rawValue) \(holdFor)")
		}
		func accessibilityTree(device: SimulatorDevice) async throws -> SimulatorAccessibilityNode {
			let percent = Int((slider.withLock(\.value) * 100).rounded())
			var children = [
				SimulatorAccessibilityNode(role: "Button", label: "Go", frame: CGRect(x: 10, y: 20, width: 30, height: 40)),
				SimulatorAccessibilityNode(role: "StaticText", label: "Welcome", frame: CGRect(x: 10, y: 80, width: 200, height: 20)),
				SimulatorAccessibilityNode(role: "TextField", identifier: "email", frame: CGRect(x: 10, y: 120, width: 300, height: 40)),
				SimulatorAccessibilityNode(role: "Switch", label: "Wi-Fi", value: "1", frame: CGRect(x: 36, y: 300, width: 330, height: 28)),
				SimulatorAccessibilityNode(role: "Slider", value: "\(percent) %", identifier: "size", frame: Slider.frame),
			]
			let loaded = loadedAfterReads.withLock { reads -> Bool in
				guard let remaining = reads else {
					return false
				}
				reads = remaining - 1
				return remaining <= 0
			}
			if loaded {
				children.append(SimulatorAccessibilityNode(role: "Button", label: "Loaded", frame: CGRect(x: 10, y: 400, width: 100, height: 40)))
			}
			return SimulatorAccessibilityNode(role: "Application", label: "Demo", frame: CGRect(x: 0, y: 0, width: 402, height: 874), children: children)
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
				let effect: SimulatorElementOutcome.Effect = element.role == "Button" ? .pressed : .tapped(element.activationPoint)
				return SimulatorElementOutcome(element: element, effect: effect)
			case let .setValue(value):
				guard element.role == "TextField" else {
					throw SimulatorElementError.notSettable(element: SimulatorAccessibilityFormatter.line(for: element))
				}
				return SimulatorElementOutcome(element: element, effect: .valueSet(readBack: value))
			case .scrollToVisible:
				return SimulatorElementOutcome(element: element, effect: .scrolled(to: element.frame.offsetBy(dx: 0, dy: -50)))
			case .increment, .decrement:
				guard element.role == "Slider" else {
					throw SimulatorElementError.notAdjustable(element: SimulatorAccessibilityFormatter.line(for: element))
				}
				let value = slider.withLock { slider in
					slider.set(slider.value + (action == .increment ? 1 : -1) * (slider.step ?? 0.1))
					return slider.value
				}
				return SimulatorElementOutcome(element: element, effect: .valueSet(readBack: "\(Int((value * 100).rounded())) %"))
			}
		}

		/// The interface follows every orientation but upside down, as on a Face ID iPhone.
		func rotate(device: SimulatorDevice, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorDevice {
			record("rotate \(orientation.rawValue)")
			var rotated = device
			rotated.rotation = orientation == .portraitUpsideDown ? device.rotation : device.interfaceRotation(for: orientation)
			return rotated
		}

		/// Open and partially open show a 669×951-point inner panel, turned landscape like the
		/// iPhone Duo's.
		func setFold(device: SimulatorDevice, to fold: SimulatorFold) async throws -> SimulatorDevice {
			record("fold \(fold.rawValue)")
			return fold.showsInnerPanel
				? SimulatorDevice(
					id: device.id,
					name: device.name,
					runtimeName: device.runtimeName,
					state: device.state,
					screenPixelSize: CGSize(width: 2007, height: 2853),
					screenScale: 3,
					rotation: .clockwise,
					fold: fold,
					screenID: 3,
					portraitRotation: .clockwise
				)
				: device
		}

		func simulateMemoryWarning(device: SimulatorDevice) async throws { record("memory warning") }
		func setLocation(device: SimulatorDevice, _ command: SimulatorLocationCommand) async throws {
			record("location \(command)")
		}
		func startRecording(device: SimulatorDevice, path: String?) async throws -> URL {
			record("start recording \(path ?? "default")")
			return URL(fileURLWithPath: path ?? "/Users/someone/Desktop/Simulator Screen Recording.mov")
		}
		var stoppedRecording = SimulatorRecording(url: URL(fileURLWithPath: "/tmp/demo.mov"), duration: .milliseconds(12_340))
		func stopRecording(udid: String?) async throws -> SimulatorRecording {
			record("stop recording \(udid ?? "default")")
			return stoppedRecording
		}

		func setUISettings(device: SimulatorDevice, _ settings: SimulatorUISettings) async throws {
			record("ui \(try settings.simctlCommands(udid: device.id).map { $0.dropFirst(2).joined(separator: " ") }.joined(separator: ", "))")
		}
		func setStatusBar(device: SimulatorDevice, _ command: SimulatorStatusBarCommand) async throws {
			record(try command.simctlArguments(udid: device.id).dropFirst(2).joined(separator: " "))
		}
		func erase(device: SimulatorDevice) async throws -> Bool {
			record("erase \(device.id)")
			return device.isBooted
		}
		func launchApp(device: SimulatorDevice, _ request: SimulatorAppLaunchRequest) async throws -> SimulatorAppLaunch {
			record("launch \(request.bundleId) \(request.arguments) capture \(request.captureLogs)")
			guard request.captureLogs else {
				return SimulatorAppLaunch(processId: 4321)
			}
			return SimulatorAppLaunch(
				processId: 4321,
				logURL: URL(fileURLWithPath: "/tmp/com.example.App.log"),
				logPredicate: request.logPredicate ?? "default"
			)
		}
		func terminateApp(device: SimulatorDevice, bundleId: String) async throws -> URL? {
			record("terminate \(bundleId)")
			return URL(fileURLWithPath: "/tmp/com.example.App.log")
		}
		func openURL(device: SimulatorDevice, _ url: String) async throws {
			record("open \(url)")
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
		SimulatorMCPHandler(actions: { _ in actions }) { reported in
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
			"type_text", "press_key", "press_button", "press_element", "set_value", "scroll_to_element", "list_crashes", "crash_report", "rotate",
			"set_fold", "wait_for_element", "set_slider", "gesture", "batch", "set_location", "simulate_memory_warning", "start_recording",
			"stop_recording", "set_appearance", "set_status_bar", "erase_device", "launch_app", "stop_app", "open_url",
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
	func actionsAreTakenForTheCallingSession() async throws {
		let actions = FakeActions()
		let sessions = OSAllocatedUnfairLock<[UUID?]>(initialState: [])
		let handler = SimulatorMCPHandler(
			actions: { sessionId in
				sessions.withLock { $0.append(sessionId) }
				return actions
			},
			onActivity: { _ in }
		)
		let session = UUID()
		let call: JSONValue = [
			"jsonrpc": "2.0", "id": 3, "method": "tools/call",
			"params": ["name": "list_devices", "arguments": [:]],
		]
		_ = await handler.response(to: try post(call, headers: ["x-bridge-commander-session": session.uuidString]))
		_ = await handler.response(to: try post(call))

		#expect(sessions.withLock { $0 } == [session, nil])
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
			("gesture", ["preset": "scroll_down"]),
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
			"press_element", "set_value", "scroll_to_element", "gesture",
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
		#expect(tapped.text == "Tapped StaticText \"Welcome\" frame=(10,80,200,20) at (110, 90): it has no accessibility press, or refused it. Screen settled after 640 ms.")

		// A switch is tapped at its trailing end, where a finger toggles it; found here by value.
		let toggled = try await callText(actions, "press_element", ["current_value": "1", "role": "switch", "wait_for_settle": false])
		#expect(toggled.text == "Tapped Switch \"Wi-Fi\" value=\"1\" frame=(36,300,330,28) tap=(335,314) at (335, 314): it has no accessibility press, or refused it.")
		#expect(actions.calls.withLock { $0 }.filter { $0.hasPrefix("element") } == ["element press Go", "element press Welcome", "element press Wi-Fi"])
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

	private func callForLastText(_ actions: FakeActions, _ name: String, _ arguments: JSONValue) async throws -> (text: String?, isError: JSONValue?) {
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
		let turned = try await callForLastText(actions, "rotate", ["orientation": "landscape_left"])
		#expect(turned.isError == false)
		#expect(turned.text == "Rotated to landscape left. The screen is now 874×402 points; take a new screenshot before using coordinates.")

		let refused = try await callForLastText(actions, "rotate", ["orientation": "portrait_upside_down"])
		#expect(refused.text?.hasPrefix("Turned the device to portrait upside down, but the interface stayed portrait") == true)
		#expect(refused.text?.hasSuffix("The screen is 402×874 points.") == true)
		#expect(actions.calls.withLock { $0 } == ["rotate landscape_left", "rotate portrait_upside_down"])

		let unknown = try await callForLastText(actions, "rotate", ["orientation": "sideways"])
		#expect(unknown.isError == true)
	}

	@Test
	func setFoldOpensADuoAndRefusesAPhone() async throws {
		let actions = FakeActions()
		let refused = try await callForLastText(actions, "set_fold", ["state": "open"])
		#expect(refused.isError == true)
		#expect(refused.text == "iPhone does not fold; only the iPhone Duo does.")

		let duo = SimulatorDevice(
			id: "AAAA",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 1398, height: 2034),
			screenScale: 3,
			fold: .closed
		)
		actions.devicesResult = [duo]
		let list = try await callForLastText(actions, "list_devices", [:])
		#expect(list.text == "iPhone Duo (iOS 27.1) AAAA — Booted, 466×678 pt, folded [shown]")

		let opened = try await callForLastText(actions, "set_fold", ["state": "open"])
		#expect(opened.isError == false)
		#expect(opened.text == "Unfolded iPhone Duo; it shows the inner panel, 951×669 points. Take a new screenshot before using coordinates.")
		#expect(actions.calls.withLock { $0 } == ["fold open"])

		let partly = try await callForLastText(actions, "set_fold", ["state": "partially_open"])
		#expect(partly.text == "Partially unfolded iPhone Duo; it shows the inner panel, 951×669 points. Take a new screenshot before using coordinates.")
		actions.devicesResult = [try await actions.setFold(device: duo, to: .partiallyOpen)]
		let partlyListed = try await callForLastText(actions, "list_devices", [:])
		#expect(partlyListed.text == "iPhone Duo (iOS 27.1) AAAA — Booted, 951×669 pt landscape, partially unfolded [shown]")

		let unknown = try await callForLastText(actions, "set_fold", ["state": "ajar"])
		#expect(unknown.isError == true)
		#expect(unknown.text == "Unknown state \"ajar\"; use open, partially_open or closed.")

		// The inner panel is mounted a quarter turn round: landscape left shows it portrait.
		actions.devicesResult = [try await actions.setFold(device: duo, to: .open)]
		let turned = try await callForLastText(actions, "rotate", ["orientation": "landscape_left"])
		#expect(turned.text == "Rotated to landscape left. The screen is now 669×951 points; take a new screenshot before using coordinates.")
	}

	@Test
	func aRotatedDeviceIsListedAndShotInLandscape() async throws {
		let actions = FakeActions()
		var rotated = Self.phone
		rotated.rotation = .clockwise
		actions.devicesResult = [rotated]

		let list = try await callForLastText(actions, "list_devices", [:])
		#expect(list.text == "iPhone (iOS 27.0) AAAA — Booted, 874×402 pt landscape [shown]")
		let shot = try await callForLastText(actions, "screenshot", [:])
		#expect(shot.text == "iPhone, 874×402 points (landscape).")
	}
	@Test
	func pressKeyTakesASequenceAndChecksItWhole() async throws {
		let actions = FakeActions()
		let pressed = try await callText(actions, "press_key", ["keys": ["cmd+a", "delete"], "wait_for_settle": false])
		#expect(pressed.text == "Pressed cmd+a, delete.")
		#expect(actions.calls.withLock { $0 } == ["keys 4,42"])

		let typo = try await callText(actions, "press_key", ["keys": ["cmd+a", "nosuchkey"]])
		#expect(typo.isError)
		#expect(typo.text == "Unknown key \"nosuchkey\".")
		#expect(actions.calls.withLock { $0.count } == 1)

		#expect(try await callText(actions, "press_key", ["keys": []]).isError)
		#expect(try await callText(actions, "press_key", [:]).isError)
	}

	@Test
	func pressButtonHoldsForTheDuration() async throws {
		let actions = FakeActions()
		_ = try await callText(actions, "press_button", ["button": "side_button", "duration_ms": 1500, "wait_for_settle": false])
		_ = try await callText(actions, "press_button", ["button": "play_pause", "wait_for_settle": false])
		#expect(actions.calls.withLock { $0 } == ["button side_button 1.5 seconds", "button play_pause 0.1 seconds"])
		#expect(try await callText(actions, "press_button", ["button": "apple_pay"]).isError)
	}

	@Test
	func setLocationTakesExactlyOneKindOfLocation() async throws {
		let actions = FakeActions()
		let point = try await callText(actions, "set_location", ["latitude": .number(50.0755), "longitude": "14.4378"])
		#expect(point.text == "iPhone is now at 50.075500, 14.437800.")

		let route = try await callText(actions, "set_location", [
			"waypoints": [["latitude": 1, "longitude": 2], ["latitude": 3, "longitude": 4]],
			"speed": 5,
		])
		#expect(route.text == "iPhone is moving along 2 waypoints at 5 m/s, with an update every second. set_location with clear stops it.")

		let scenario = try await callText(actions, "set_location", ["scenario": "City Run"])
		#expect(scenario.text == "iPhone is running the \"City Run\" location scenario. set_location with clear stops it.")

		let cleared = try await callText(actions, "set_location", ["clear": "true"])
		#expect(cleared.text == "Cleared iPhone's simulated location.")
		#expect(actions.calls.withLock { $0.count } == 4)

		for arguments: JSONValue in [
			[:],
			["latitude": 1],
			["latitude": 1, "longitude": 2, "scenario": "City Run"],
			["waypoints": [["latitude": 1]]],
			["clear": false],
		] {
			#expect(try await callText(actions, "set_location", arguments).isError, "\(arguments)")
		}
		#expect(actions.calls.withLock { $0.count } == 4)
	}

	@Test
	func memoryWarningIsSent() async throws {
		let actions = FakeActions()
		let sent = try await callText(actions, "simulate_memory_warning", [:])
		#expect(sent.text == "Sent a memory warning to the apps on iPhone.")
		#expect(actions.calls.withLock { $0 } == ["memory warning"])
	}

	@Test
	func recordingStartsAndStops() async throws {
		let actions = FakeActions()
		let activity = OSAllocatedUnfairLock<[SimulatorActivity]>(initialState: [])
		let started = try await decode(handler(actions, activity: activity).response(to: post([
			"jsonrpc": "2.0", "id": 1, "method": "tools/call",
			"params": ["name": "start_recording", "arguments": ["path": "/tmp/flow.mov"]],
		])))["result"]?["content"]?.firstText
		#expect(started == "Recording iPhone to /tmp/flow.mov. Call stop_recording to save it; it stops on its own after 10 minutes.")
		#expect(activity.withLock { $0.map(\.deviceId) } == ["AAAA"])

		let stopped = try await callText(actions, "stop_recording", [:])
		#expect(stopped.text == "Saved the recording (12.3 seconds) to /tmp/demo.mov.")

		actions.stoppedRecording.endedEarly = "it reached the 10-minute limit"
		let ended = try await callText(actions, "stop_recording", ["udid": "aaaa"])
		#expect(ended.text == "The recording had already stopped — it reached the 10-minute limit — and was saved to /tmp/demo.mov (12.3 seconds).")
		#expect(actions.calls.withLock { $0 } == ["start recording /tmp/flow.mov", "stop recording default", "stop recording aaaa"])
	}

	@Test
	func appearanceSetsOnlyWhatIsGiven() async throws {
		let actions = FakeActions()
		let dark = try await callText(actions, "set_appearance", ["appearance": "dark"])
		#expect(dark.text == "Set iPhone to dark mode.")
		let all = try await callText(actions, "set_appearance", [
			"appearance": "light", "content_size": "accessibility-large", "increase_contrast": true,
		])
		#expect(all.text == "Set iPhone to light mode, text size accessibility-large, Increase Contrast on.")
		#expect(actions.calls.withLock { $0 } == [
			"ui appearance dark",
			"ui appearance light, content_size accessibility-large, increase_contrast enabled",
		])
		#expect(try await callText(actions, "set_appearance", ["appearance": "sepia"]).isError)
		#expect(try await callText(actions, "set_appearance", [:]).isError)
		#expect(try await callText(actions, "set_appearance", ["content_size": "huge"]).isError)
	}

	@Test
	func statusBarStartsFromCleanAndClearsAlone() async throws {
		let actions = FakeActions()
		let clean = try await callText(actions, "set_status_bar", ["clean": true, "battery_level": 42, "data_network": "5g"])
		#expect(clean.text == "Overrode iPhone's status bar. set_status_bar with clear removes the override.")
		_ = try await callText(actions, "set_status_bar", ["time": "10:00"])
		let cleared = try await callText(actions, "set_status_bar", ["clear": true])
		#expect(cleared.text == "Cleared iPhone's status bar override.")
		#expect(actions.calls.withLock { $0 } == [
			"override --time 9:41 --dataNetwork 5g --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName  --batteryState charged --batteryLevel 42",
			"override --time 10:00",
			"clear",
		])
		for arguments: JSONValue in [[:], ["clear": true, "time": "9:41"], ["wifi_bars": .number(1.5)], ["battery_level": 101], ["data_network": "6g"]] as [JSONValue] {
			#expect(try await callText(actions, "set_status_bar", arguments).isError, "\(arguments)")
		}
	}

	@Test
	func eraseNeedsTheDevicesUdid() async throws {
		let actions = FakeActions()
		let missing = try await callText(actions, "erase_device", [:])
		#expect(missing.isError)
		#expect(try await callText(actions, "erase_device", ["udid": "BBBB"]).isError)
		let erased = try await callText(actions, "erase_device", ["udid": "aaaa"])
		#expect(erased.text == "Erased iPhone and booted it again; it is as new, with no apps of yours installed.")
		#expect(actions.calls.withLock { $0 } == ["erase AAAA"])
	}

	@Test
	func launchAppNamesTheLogFile() async throws {
		let actions = FakeActions()
		let launched = try await callText(actions, "launch_app", [
			"bundle_id": "com.example.App", "arguments": ["-UITesting", "YES"], "environment": ["MODE": "demo", "COUNT": 3],
		])
		#expect(launched.text == """
		Launched com.example.App on iPhone (pid 4321). Its output and log go to /tmp/com.example.App.log until it exits; read it with tail or grep.
		os_log messages kept: default
		""")
		let plain = try await callText(actions, "launch_app", ["bundle_id": "com.example.App", "capture_logs": false])
		#expect(plain.text == "Launched com.example.App on iPhone (pid 4321).")
		let stopped = try await callText(actions, "stop_app", ["bundle_id": "com.example.App"])
		#expect(stopped.text == "Terminated com.example.App on iPhone. Its captured output is in /tmp/com.example.App.log.")
		let opened = try await callText(actions, "open_url", ["url": "myapp://item/1"])
		#expect(opened.text == "Opened myapp://item/1 on iPhone. Take a screenshot to see what handled it.")
		#expect(actions.calls.withLock { $0 } == [
			"launch com.example.App [\"-UITesting\", \"YES\"] capture true",
			"launch com.example.App [] capture false",
			"terminate com.example.App",
			"open myapp://item/1",
		])
		#expect(try await callText(actions, "launch_app", [:]).isError)
		#expect(try await callText(actions, "launch_app", ["bundle_id": "com.example.App", "arguments": "-flag"]).isError)
	}

	@Test
	func launchRequestReadsEnvironmentAndPredicate() throws {
		let request = try SimulatorAppTools.launchRequest(from: [
			"bundle_id": "com.example.App", "environment": ["MODE": "demo", "COUNT": 3], "log_predicate": "  ",
		])
		#expect(request.environment == ["MODE": "demo", "COUNT": "3"])
		#expect(request.logPredicate == nil)
		#expect(request.captureLogs)
	}

	// MARK: - Waiting, sliders, gestures, batches

	@Test
	func waitForElementFindsWhatAppearsAndWhatIsGone() async throws {
		let actions = FakeActions()
		actions.loadedAfterReads.withLock { $0 = 2 }
		let found = try await callText(actions, "wait_for_element", ["label": "Loaded", "timeout_ms": 5000])
		#expect(found.isError == false)
		#expect(found.text?.hasPrefix("Found Button \"Loaded\" frame=(10,400,100,40) after 0.") == true, "\(found.text ?? "nil")")

		let gone = try await callText(FakeActions(), "wait_for_element", ["label": "Nowhere", "gone": true])
		#expect(gone.text == "No element matches label \"Nowhere\" after 0.0 s.")

		let missing = try await callText(FakeActions(), "wait_for_element", ["label": "Nowhere", "timeout_ms": 0])
		#expect(missing.isError)
		#expect(missing.text?.hasPrefix("Waited 0.0 s. No element matches label \"Nowhere\". Elements on screen:") == true)

		let stays = try await callText(FakeActions(), "wait_for_element", ["label": "Go", "gone": true, "timeout_ms": 0])
		#expect(stays.isError)
		#expect(stays.text == "Button \"Go\" frame=(10,20,30,40) is still on screen after 0.0 s.")
	}

	@Test
	func elementToolsWaitForTheirElementWithATimeout() async throws {
		let actions = FakeActions()
		actions.loadedAfterReads.withLock { $0 = 1 }
		let pressed = try await callText(actions, "press_element", ["label": "Loaded", "timeout_ms": 3000, "wait_for_settle": false])
		#expect(pressed.text == "Tapped Button \"Loaded\" frame=(10,400,100,40) at (60, 420): it has no accessibility press, or refused it."
			|| pressed.text == "Pressed Button \"Loaded\" frame=(10,400,100,40) (AXPress).")

		let late = FakeActions()
		late.loadedAfterReads.withLock { $0 = 100 }
		#expect(try await callText(late, "press_element", ["label": "Loaded", "wait_for_settle": false]).isError)
	}

	@Test
	func setSliderDragsAndCorrectsTowardTheTarget() async throws {
		let actions = FakeActions()
		// Increments take it to 70 %; a drag overshoots to 74 % on the guessed track, a second one
		// corrects it.
		let moved = try await callText(actions, "set_slider", ["identifier": "size", "value": 73])
		#expect(moved.isError == false)
		#expect(moved.text == "Moved Slider value=\"73 %\" id=size frame=(20,700,362,80) from \"50 %\" to \"73 %\".", "\(moved.text ?? "nil")")
		#expect(actions.calls.withLock { $0 }.filter { $0.hasPrefix("element") } == ["element increment size", "element increment size", "element increment size", "element decrement size"])
		#expect(actions.calls.withLock { $0 }.filter { $0.hasPrefix("swipe") }.count == 2)

		let already = try await callText(actions, "set_slider", ["value": 73])
		#expect(already.text == "Slider value=\"73 %\" id=size frame=(20,700,362,80) is already at 73 %.")

		#expect(try await callText(actions, "set_slider", ["value": 120]).isError)
		#expect(try await callText(actions, "set_slider", ["label": "Go", "value": 10]).isError)
	}

	@Test
	func setSliderStopsAtTheNearestStep() async throws {
		let actions = FakeActions()
		actions.slider.withLock { $0.step = 1.0 / 6 }
		let moved = try await callText(actions, "set_slider", ["value": 80])
		#expect(moved.text == "Moved Slider value=\"83 %\" id=size frame=(20,700,362,80) from \"50 %\" toward 80 %: it now reads \"83 %\", as close as it goes (it moves in steps).", "\(moved.text ?? "nil")")
	}

	@Test
	func sliderValuesAreReadAsFractions() {
		#expect(SimulatorSliderValue.fraction(from: "50 %") == 0.5)
		#expect(SimulatorSliderValue.fraction(from: "50\u{202F}%") == 0.5)
		#expect(SimulatorSliderValue.fraction(from: "%25") == 0.25)
		#expect(SimulatorSliderValue.fraction(from: "12,5 %") == 0.125)
		#expect(SimulatorSliderValue.fraction(from: "0.3") == 0.3)
		#expect(SimulatorSliderValue.fraction(from: "75") == 0.75)
		#expect(SimulatorSliderValue.fraction(from: "3 stars") == nil)
		#expect(SimulatorSliderValue.fraction(from: "250") == nil)
		#expect(SimulatorSliderValue.fraction(from: nil) == nil)
	}

	@Test
	func sliderTrackIsMeasuredFromBigEnoughMoves() {
		var track = SimulatorSliderTrack(frame: CGRect(x: 20, y: 0, width: 362, height: 80))
		#expect(track.x(for: 0) == 34)
		#expect(track.width == 334)
		track.calibrate(fingerMoved: 10, valueMoved: 0.01)
		#expect(track.width == 334)
		track.calibrate(fingerMoved: 131, valueMoved: 0.5)
		#expect(track.width == 262)
		track.calibrate(fingerMoved: -100, valueMoved: 0.5)
		#expect(track.width == 262)
	}

	@Test
	func gesturePresetsAreSizedFromTheScreen() async throws {
		let size = CGSize(width: 402, height: 874)
		let down = SimulatorGesturePreset.scrollDown.path(in: size)
		#expect(down.from == CGPoint(x: 201, y: 655.5))
		#expect(down.to == CGPoint(x: 201, y: 218.5))
		#expect(SimulatorGesturePreset.scrollLeft.path(in: size, distance: 100).to == CGPoint(x: 251, y: 437))
		#expect(SimulatorGesturePreset.swipeFromLeftEdge.path(in: size).from == CGPoint(x: 2, y: 437))
		let controlCenter = SimulatorGesturePreset.swipeFromTopEdge.path(in: size, position: CGPoint(x: 380, y: 437))
		#expect(controlCenter.from == CGPoint(x: 380, y: 2))
		#expect(SimulatorGesturePreset.swipeFromBottomEdge.path(in: size).from == CGPoint(x: 201, y: 872))

		let actions = FakeActions()
		let back = try await callText(actions, "gesture", ["preset": "swipe_from_left_edge", "y": 300, "wait_for_settle": false])
		#expect(back.text == "swipe_from_left_edge: swiped from (2, 300) to (281.4, 300).")
		#expect(actions.calls.withLock { $0 } == ["swipe 2.0,300.0 281.4,300.0"])
		#expect(try await callText(actions, "gesture", ["preset": "shake"]).isError)
	}

	@Test
	func swipeCanHoldBeforeMoving() async throws {
		let actions = FakeActions()
		let dragged = try await callText(actions, "swipe", ["from_x": 50, "from_y": 100, "to_x": 50, "to_y": 400, "hold_ms": 600, "wait_for_settle": false])
		#expect(dragged.text == "Swiped from (50, 100) to (50, 400) after holding 600 ms.")
		#expect(actions.calls.withLock { $0 } == ["swipe 50.0,100.0 50.0,400.0 hold 0.6 seconds"])
	}

	@Test
	func batchRunsStepsInOrderAndCollectsScreenshots() async throws {
		let actions = FakeActions()
		let response = await handler(actions).response(to: try post([
			"jsonrpc": "2.0", "id": 1, "method": "tools/call",
			"params": ["name": "batch", "arguments": ["steps": [
				["tool": "tap", "x": 10, "y": 20, "wait_for_settle": false],
				["tool": "sleep", "duration_ms": 10],
				["tool": "type_text", "text": "hi", "wait_for_settle": false],
				["tool": "screenshot"],
			]]],
		]))
		let result = try decode(response)["result"]
		guard case let .array(content)? = result?["content"] else {
			Issue.record("expected content")
			return
		}
		#expect(result?["isError"] == false)
		#expect(content.first?["text"] == """
		Ran 4 steps.
		1. tap: Tapped (10, 20).
		2. sleep: waited 0.0 s.
		3. type_text: Typed 2 characters.
		4. screenshot: iPhone, 402×874 points.
		""")
		#expect(content.count == 2)
		#expect(content.last?["type"] == "image")
		#expect(actions.calls.withLock { $0 } == ["tap 10.0 20.0 0.06 seconds", "type hi"])
	}

	@Test
	func batchStopsAtAFailureUnlessToldToGoOn() async throws {
		let steps: JSONValue = [
			["tool": "press_key", "key": "warp"],
			["tool": "tap", "x": 1, "y": 1, "wait_for_settle": false],
		]
		let stopping = FakeActions()
		let stopped = try await callText(stopping, "batch", ["steps": steps])
		#expect(stopped.isError)
		#expect(stopped.text == """
		1 of 2 steps failed.
		1. press_key FAILED: Unknown key "warp".
		Stopped at step 1; the last step was not run.
		""")
		#expect(stopping.calls.withLock { $0 }.isEmpty)

		let going = FakeActions()
		let went = try await callText(going, "batch", ["steps": steps, "continue_on_error": true])
		#expect(went.isError)
		#expect(going.calls.withLock { $0 } == ["tap 1.0 1.0 0.06 seconds"])

		// Checked whole before anything runs.
		let checked = FakeActions()
		let refused = try await callText(checked, "batch", ["steps": [["tool": "tap", "x": 1, "y": 1], ["tool": "batch"]]])
		#expect(refused.isError)
		#expect(refused.text?.hasPrefix("Step 2: \"batch\" cannot be a batch step") == true)
		#expect(checked.calls.withLock { $0 }.isEmpty)
		#expect(try await callText(checked, "batch", ["steps": []]).isError)
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
