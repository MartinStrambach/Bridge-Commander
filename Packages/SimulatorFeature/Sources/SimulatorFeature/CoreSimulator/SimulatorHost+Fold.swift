import Foundation
import os

/// Opening and closing a device that folds — the iPhone Duo — and keeping track of which of its
/// panels it shows.
///
/// CoreSimulator does not say whether such a device is open: both panels stay powered and lit
/// either way, and the one not in use just shows black. So the state is the one last set from
/// here during the device's current boot (a fresh boot starts closed), recorded per boot so a
/// restart of the app keeps it. A fold made elsewhere — in Xcode's DeviceHub — is not seen.
extension SimulatorHost {
	/// Each open device's UDID, mapped to the `lastBootedAt` of the boot it was opened in (as
	/// `timeIntervalSinceReferenceDate`, under `boot`) and how far it is open (`fold`, a
	/// `SimulatorFold` raw value).
	private static let openDevicesKey = "simulatorOpenFoldableDevices"
	/// The inner panel of each device that is open now, set whenever a device is read, for the
	/// calls that are given only a UDID (the pane's screen, rotation). Calls given a
	/// `SimulatorDevice` go by its `screenID` instead.
	private static let openPanels = OSAllocatedUnfairLock<[String: SimulatorFoldDisplays.Panel]>(initialState: [:])

	static func foldDisplays(of device: AnyObject) -> SimulatorFoldDisplays? {
		guard
			let deviceType = ObjCRuntime.object(device, "deviceType"),
			let capabilities = ObjCRuntime.object(deviceType, "capabilities") as? [String: Any]
		else {
			return nil
		}
		return SimulatorFoldDisplays(capabilities: capabilities)
	}

	/// How far `device` is open now, refreshing what touches and the screen lookup go by.
	static func fold(of device: AnyObject, udid: String, displays: SimulatorFoldDisplays, isBooted: Bool) -> SimulatorFold {
		let boot = bootKey(of: device)
		return openPanels.withLock { panels in
			let record = UserDefaults.standard.dictionary(forKey: openDevicesKey)?[udid] as? [String: Any]
			let fold = isBooted && record?["boot"] as? Double == boot
				? (record?["fold"] as? String).flatMap(SimulatorFold.init(rawValue:)) ?? .closed
				: .closed
			panels[udid] = fold.showsInnerPanel ? displays.inner : nil
			return fold
		}
	}

	private static func record(_ fold: SimulatorFold, udid: String, device: AnyObject, displays: SimulatorFoldDisplays) {
		let boot = bootKey(of: device)
		openPanels.withLock { panels in
			var open = UserDefaults.standard.dictionary(forKey: openDevicesKey) ?? [:]
			open[udid] = fold.showsInnerPanel ? ["boot": boot, "fold": fold.rawValue] : nil
			UserDefaults.standard.set(open, forKey: openDevicesKey)
			panels[udid] = fold.showsInnerPanel ? displays.inner : nil
		}
	}

	/// Tells one boot from the next; `bootSessionUUID` is nil on these runtimes.
	private static func bootKey(of device: AnyObject) -> Double {
		(ObjCRuntime.object(device, "lastBootedAt") as? Date)?.timeIntervalSinceReferenceDate ?? 0
	}

	/// The panel shown instead of the main screen, if any: an open device's inner panel.
	static func openPanel(udid: String) -> SimulatorFoldDisplays.Panel? {
		openPanels.withLock { $0[udid] }
	}

	/// Opens, partially opens or closes a device that folds, and returns it as it then is, once
	/// SpringBoard has moved the interface to the other panel.
	public func setFold(device: SimulatorDevice, to fold: SimulatorFold) async throws -> SimulatorDevice {
		let simDevice = try simDevice(udid: device.id)
		guard let displays = Self.foldDisplays(of: simDevice) else {
			throw SimulatorError.notFoldable(device.name)
		}
		try await sendDeviceState(SimulatorDeviceStateReport.hinge(angle: fold.hingeAngle), udid: device.id)
		Self.record(fold, udid: device.id, device: simDevice, displays: displays)

		guard let folded = try devices().first(where: { $0.id == device.id }) else {
			throw SimulatorError.deviceNotFound(device.id)
		}
		_ = await waitForScreenToSettle(device: folded)
		// SpringBoard defers orientation changes while it moves the interface between the panels
		// ("Display content mode transition"), past the screen settling: a rotation sent at once
		// was dropped about half the time, one sent 0.5 s or more later never (checked live,
		// 2026-10-08). Returning a little later keeps a rotation right after a fold from vanishing.
		try await Task.sleep(for: .seconds(1))
		return try devices().first(where: { $0.id == device.id }) ?? folded
	}
}
