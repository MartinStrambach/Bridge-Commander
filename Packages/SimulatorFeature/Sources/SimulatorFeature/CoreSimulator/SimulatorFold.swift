import CoreGraphics
import Foundation
import IOKit

/// How far a device that folds — the iPhone Duo — is open: closed, showing its cover screen, or
/// partially or fully open, showing the larger inner panel.
public enum SimulatorFold: String, CaseIterable, Equatable, Sendable {
	case closed
	case partiallyOpen = "partially_open"
	case open

	/// The hinge angle that sets it, in degrees. SpringBoard moves the interface to the inner panel
	/// when the hinge opens past the cover — a single report of 130 from 0 does it, as 180 does —
	/// and back to the cover at 0; from open, 130 keeps the inner panel (checked live, 2026-10-08).
	/// 130 is where Xcode 27.1's DeviceHub leaves the hinge for its partial unfold; the guest's
	/// `locationd` reports it as partly open (`propertyB` 2) rather than flat (3).
	var hingeAngle: Double {
		switch self {
		case .closed:
			0
		case .partiallyOpen:
			130
		case .open:
			180
		}
	}

	/// Whether the device shows its inner panel rather than the cover.
	public var showsInnerPanel: Bool {
		self != .closed
	}

	public var label: String {
		switch self {
		case .closed:
			"folded"
		case .partiallyOpen:
			"partially unfolded"
		case .open:
			"unfolded"
		}
	}

	public var title: String {
		switch self {
		case .closed:
			"Closed"
		case .partiallyOpen:
			"Partially Open"
		case .open:
			"Open"
		}
	}

	/// What the pane's Fold/Unfold button switches to: a closed device opens fully, a partially
	/// or fully open one closes.
	public var toggled: SimulatorFold {
		showsInnerPanel ? .closed : .open
	}
}

/// The two panels of a device that folds, from its device type's capabilities: the cover, which
/// the closed device shows and which is its main screen, and the inner panel the open one shows.
struct SimulatorFoldDisplays: Equatable, Sendable {
	struct Panel: Equatable, Sendable {
		/// The screen's ID: `screenProperties.screenID`, and the digitizer's `target`.
		let screenID: UInt32
		/// Portrait, as the framebuffer is.
		let pixelSize: CGSize
		let scale: CGFloat
		/// The interface's rotation on this panel while the device is held portrait. The inner
		/// panel is mounted turned (`nativeRotation` 270), so it shows the interface a quarter
		/// turn clockwise then — landscape — and every orientation one quarter on from the cover's.
		var portraitRotation: SimulatorScreenRotation = .upright
	}

	let cover: Panel
	let inner: Panel

	/// From `-[SimDeviceType capabilities]`, whose `capabilities.displays` lists every screen the
	/// device type has; the panels are the `integrated` ones, the cover first by screen ID (1, the
	/// inner panel 3 on the iPhone Duo). Nil for a device with one panel.
	init?(capabilities: [String: Any]) {
		guard
			let body = capabilities["capabilities"] as? [String: Any],
			let displays = body["displays"] as? [[String: Any]]
		else {
			return nil
		}
		let panels = displays
			.filter { $0["displayType"] as? String == "integrated" }
			.compactMap { display -> Panel? in
				guard
					let screenID = (display["screenID"] as? NSNumber)?.uint32Value,
					let width = (display["width"] as? NSNumber)?.doubleValue,
					let height = (display["height"] as? NSNumber)?.doubleValue,
					let scale = (display["scale"] as? NSNumber)?.doubleValue
				else {
					return nil
				}
				let nativeRotation = (display["nativeRotation"] as? NSNumber)?.intValue ?? 0
				return Panel(
					screenID: screenID,
					pixelSize: CGSize(width: width, height: height),
					scale: scale,
					portraitRotation: SimulatorScreenRotation(quarterTurns: (360 - nativeRotation) / 90)
				)
			}
			.sorted { $0.screenID < $1.screenID }
		guard panels.count == 2 else {
			return nil
		}
		self.cover = panels[0]
		self.inner = panels[1]
	}

	init(cover: Panel, inner: Panel) {
		self.cover = cover
		self.inner = inner
	}

	func panel(for fold: SimulatorFold) -> Panel {
		fold.showsInnerPanel ? inner : cover
	}
}

/// The vendor-defined HID reports of the guest's virtual-machine controls — DeviceHub's hinge
/// slider and orientation picker — as Xcode 27.1 sends them (`CoreDevicePopDeviceKitExtension`,
/// through `CoreDevice.HIDVendorDefined`) and idb does (`SimulatorHingeAngle`,
/// `SimulatorHIDOrientation`, MIT): a binary-serialized CF dictionary, which the guest's `locationd`
/// (`CMDeviceStateRelayManager`) turns into the device state SpringBoard follows. Only a runtime
/// that reports device motion acts on them — of the iOS 27 ones, the iPhone Duo's.
enum SimulatorDeviceStateReport {
	static let usagePage: UInt64 = 0xFF61
	static let usage: UInt64 = 0x5B

	static func hinge(angle: Double) -> Data {
		control(source: "hinge-slider-control", type: "range", value: min(max(angle, 0), 180))
	}

	static func orientation(_ orientation: SimulatorDeviceOrientation) -> Data {
		control(source: "orientation-picker-control", type: "enum", value: orientation.deviceStateValue)
	}

	private static func control(source: String, type: String, value: Any) -> Data {
		let body: [String: Any] = [
			"provider": "com.apple.Virtualization.VirtualMachines",
			"source": source,
			"type": type,
			"value": value,
		]
		return IOCFSerialize(body as CFDictionary, CFOptionFlags(kIOCFSerializeToBinary)) as Data? ?? Data()
	}
}
