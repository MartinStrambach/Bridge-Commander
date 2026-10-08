import CoreGraphics
import Foundation
import IOKit
import Testing
@testable import SimulatorFeature

struct SimulatorFoldTests {
	/// The iPhone Duo's `capabilities.displays`, trimmed to the keys read, as Xcode 27.1 lists them.
	private static var duoCapabilities: [String: Any] {
		[
			"capabilities": [
				"displays": [
					[
						"deviceName": "primary", "displayType": "integrated", "screenID": 1, "width": 1398, "height": 2034, "scale": 3,
						"nativeRotation": 0,
					],
					[
						"deviceName": "primary-1", "displayType": "integrated", "screenID": 3, "width": 2007, "height": 2853, "scale": 3,
						"nativeRotation": 270,
					],
					["deviceName": "external-0", "displayType": "tvOut", "screenID": 2, "width": 720, "height": 480, "scale": 1],
					["deviceName": "wireless0", "displayType": "carPlay", "screenID": 4, "width": 720, "height": 480, "scale": 1],
					["deviceName": "resizable", "displayType": "scene", "screenID": 5, "width": 7680, "height": 4320, "scale": 3],
				],
			],
		]
	}

	@Test
	func theDuosPanelsAreItsTwoIntegratedDisplays() throws {
		let displays = try #require(SimulatorFoldDisplays(capabilities: Self.duoCapabilities))
		#expect(displays.cover == .init(screenID: 1, pixelSize: CGSize(width: 1398, height: 2034), scale: 3))
		#expect(displays.inner == .init(screenID: 3, pixelSize: CGSize(width: 2007, height: 2853), scale: 3, portraitRotation: .clockwise))
		#expect(displays.panel(for: .open) == displays.inner)
		#expect(displays.panel(for: .closed) == displays.cover)
	}

	@Test
	func aDeviceWithOnePanelDoesNotFold() {
		let phone: [String: Any] = [
			"capabilities": [
				"displays": [
					["displayType": "integrated", "screenID": 1, "width": 1206, "height": 2622, "scale": 3],
					["displayType": "tvOut", "screenID": 2, "width": 720, "height": 480, "scale": 1],
				],
			],
		]
		#expect(SimulatorFoldDisplays(capabilities: phone) == nil)
		#expect(SimulatorFoldDisplays(capabilities: [:]) == nil)
	}

	private static func decode(_ data: Data) throws -> [String: Any] {
		try #require(data.withUnsafeBytes { bytes in
			IOCFUnserializeWithSize(bytes.baseAddress!.assumingMemoryBound(to: CChar.self), bytes.count, nil, 0, nil) as? [String: Any]
		})
	}

	@Test
	func theHingeReportIsTheSerializedDictionaryDeviceHubSends() throws {
		let decoded = try Self.decode(SimulatorDeviceStateReport.hinge(angle: SimulatorFold.open.hingeAngle))
		#expect(decoded["provider"] as? String == "com.apple.Virtualization.VirtualMachines")
		#expect(decoded["source"] as? String == "hinge-slider-control")
		#expect(decoded["type"] as? String == "range")
		#expect((decoded["value"] as? NSNumber)?.doubleValue == 180)
		#expect(SimulatorDeviceStateReport.usagePage == 0xFF61)
		#expect(SimulatorDeviceStateReport.usage == 0x5B)
	}

	@Test
	func theOrientationReportNamesTheOrientationAsThePickerDoes() throws {
		let decoded = try Self.decode(SimulatorDeviceStateReport.orientation(.landscapeLeft))
		#expect(decoded["source"] as? String == "orientation-picker-control")
		#expect(decoded["type"] as? String == "enum")
		#expect(decoded["value"] as? String == "landscape-left")
		#expect(SimulatorDeviceOrientation.allCases.map(\.deviceStateValue) == ["portrait", "landscape-left", "landscape-right", "pud"])
	}

	/// What the open Duo's inner panel showed for each orientation, read live.
	@Test
	func theInnerPanelShowsEachOrientationAQuarterTurnOn() {
		let inner = SimulatorDevice(
			id: "D",
			name: "iPhone Duo",
			runtimeName: "iOS 27.1",
			state: .booted,
			screenPixelSize: CGSize(width: 2007, height: 2853),
			screenScale: 3,
			fold: .open,
			screenID: 3,
			portraitRotation: .clockwise
		)
		#expect(inner.interfaceRotation(for: .portrait) == .clockwise)
		#expect(inner.interfaceRotation(for: .landscapeLeft) == .upright)
		#expect(inner.interfaceRotation(for: .portraitUpsideDown) == .counterclockwise)
		#expect(inner.interfaceRotation(for: .landscapeRight) == .upsideDown)
		#expect(SimulatorScreenRotation(quarterTurns: -1) == .counterclockwise)
		#expect(SimulatorScreenRotation(quarterTurns: 5) == .clockwise)
	}

	@Test
	func closingSetsTheHingeFlatShut() {
		#expect(SimulatorFold.closed.hingeAngle == 0)
		#expect(SimulatorFold.closed.toggled == .open)
		#expect(SimulatorFold.open.toggled == .closed)
	}

	/// SpringBoard's Settings icon on the open Duo's inner panel, as read live: native portrait
	/// frame (52, 417.33, 86.67, 68) on the 669×951-point panel, which shows landscape.
	@Test
	func springBoardFramesOnTheInnerPanelAreTurnedToTheInterface() {
		let display = SimulatorAccessibilityDisplay(id: 3, panel: .init(rotation: .clockwise, nativeSize: CGSize(width: 669, height: 951)))
		let icon = SimulatorAccessibilityNode(role: "Button", label: "Settings", frame: CGRect(x: 52, y: 417, width: 87, height: 68))
		let root = SimulatorAccessibilityNode(role: "Application", frame: CGRect(x: 0, y: 0, width: 466, height: 678), children: [icon])

		let home = display.interfaceTree(root, isSpringBoard: true)
		#expect(home.frame == CGRect(x: 0, y: 0, width: 951, height: 669))
		#expect(home.children.first?.frame == CGRect(x: 466, y: 52, width: 68, height: 87))

		// Apps report their frames in the interface's space already; only the root is fixed.
		let app = display.interfaceTree(root, isSpringBoard: false)
		#expect(app.frame == CGRect(x: 0, y: 0, width: 951, height: 669))
		#expect(app.children.first?.frame == icon.frame)

		#expect(SimulatorAccessibilityDisplay.main.interfaceTree(root, isSpringBoard: true) == root)
	}

	@Test
	func aRectTurnsWithItsCorners() {
		let native = CGSize(width: 10, height: 20)
		let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
		#expect(SimulatorScreenRotation.upright.displayedRect(fromNative: rect, nativeSize: native) == rect)
		#expect(SimulatorScreenRotation.clockwise.displayedRect(fromNative: rect, nativeSize: native) == CGRect(x: 14, y: 1, width: 4, height: 3))
		#expect(SimulatorScreenRotation.counterclockwise.displayedRect(fromNative: rect, nativeSize: native) == CGRect(x: 2, y: 6, width: 4, height: 3))
		#expect(SimulatorScreenRotation.upsideDown.displayedRect(fromNative: rect, nativeSize: native) == CGRect(x: 6, y: 14, width: 3, height: 4))
	}
}
