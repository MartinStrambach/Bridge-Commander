import Darwin
import Foundation
import os
import XPC

/// Rotating the device, and reading which way it and its interface are turned.
///
/// On Xcode 27 the rotation is a GSEvent sent to SpringBoard's `PurpleWorkspacePort`, as
/// Simulator.app's `sendPurpleEvent:` does and idb does for runtimes without device motion. idb's
/// other route, an orientation-picker report on `dtuhidd`'s vendor-defined service, is accepted
/// and ignored by the iOS 27 runtimes, which report `deviceMotionState: false` (checked live,
/// 2026-10-07).
extension SimulatorHost {
	private static let purpleQueue = DispatchQueue(label: "com.bridgecommander.simulator.purple")
	private static let orientationService = "com.apple.coredevice.feature.remote.devicecontrol.orientation"

	// MARK: - Reading

	/// How the main screen's interface is turned now.
	public func screenRotation(udid: String) throws -> SimulatorScreenRotation {
		try Self.screenRotation(of: mainScreen(udid: udid))
	}

	/// `-[SimScreen screenProperties].uiOrientation`, which follows the interface (an app that
	/// stays portrait keeps it at portrait while the device turns).
	static func screenRotation(of screen: AnyObject) -> SimulatorScreenRotation {
		guard
			ObjCRuntime.responds(screen, to: "screenProperties"),
			let properties = ObjCRuntime.object(screen, "screenProperties")
		else {
			return .upright
		}
		return screenRotation(ofProperties: properties)
	}

	/// Reads the rotation from a screen-properties object: what `screenProperties` returns, and what
	/// the screen's properties-changed callback delivers.
	static func screenRotation(ofProperties properties: AnyObject) -> SimulatorScreenRotation {
		guard ObjCRuntime.responds(properties, to: "uiOrientation") else {
			return .upright
		}
		// Only the low 32 bits: the proxy may return a 32-bit integer.
		let value = UInt(UInt32(truncatingIfNeeded: ObjCRuntime.unsignedInteger(properties, "uiOrientation")))
		return SimulatorScreenRotation(uiOrientation: value)
	}

	/// Which way the device is held, from the guest's orientation service. A device that has not
	/// been turned since boot reports `unknown`, and a flat one `faceUp`/`faceDown`; for those the
	/// last upright orientation is used, and portrait if there is none.
	public func deviceOrientation(udid: String) async throws -> SimulatorDeviceOrientation {
		let connection = try SimulatorHIDConnection.makeConnection(device: simDevice(udid: udid), service: Self.orientationService)
		xpc_connection_set_target_queue(connection, Self.purpleQueue)
		xpc_connection_set_event_handler(connection) { _ in }
		xpc_connection_resume(connection)
		defer { xpc_connection_cancel(connection) }

		let payload = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_value(payload, "currentOrientation", xpc_dictionary_create(nil, nil, 0))
		let message = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_string(message, "messageType", "OrientationRequest")
		xpc_dictionary_set_bool(message, "isBarrier", false)
		xpc_dictionary_set_string(message, "featureIdentifier", Self.orientationService)
		xpc_dictionary_set_value(message, "payload", payload)

		let reply = await Self.reply(to: message, on: connection, timeout: .seconds(3))
		guard let reply, xpc_get_type(reply) == XPC_TYPE_DICTIONARY else {
			throw SimulatorError.inputUnavailable("the orientation service did not answer")
		}
		for key in ["currentDeviceOrientation", "currentDeviceNonFlatOrientation"] {
			if let name = xpc_dictionary_get_string(reply, key),
			   let orientation = SimulatorDeviceOrientation(guestName: String(cString: name)) {
				return orientation
			}
		}
		return .portrait
	}

	private static func reply(to message: xpc_object_t, on connection: xpc_connection_t, timeout: Duration) async -> xpc_object_t? {
		final class Reply: @unchecked Sendable {
			let object: xpc_object_t?

			init(_ object: xpc_object_t?) {
				self.object = object
			}
		}
		let reply: Reply = await withCheckedContinuation { continuation in
			let once = OSAllocatedUnfairLock(initialState: false)
			let resume: @Sendable (Reply) -> Void = { value in
				let first = once.withLock { done in
					defer { done = true }
					return !done
				}
				if first {
					continuation.resume(returning: value)
				}
			}
			xpc_connection_send_message_with_reply(connection, message, nil) { object in
				resume(Reply(object))
			}
			let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
			DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
				resume(Reply(nil))
			}
		}
		return reply.object
	}

	// MARK: - Rotating

	/// Turns the device to `orientation` and returns the device as it then is. Waits for the
	/// interface to follow — or, when the frontmost app does not support the orientation, for it
	/// not to — so a screenshot taken next shows the settled screen.
	public func rotate(device: SimulatorDevice, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorDevice {
		var rotated = device
		rotated.rotation = try await rotate(udid: device.id, to: orientation)
		return rotated
	}

	/// Turns the device a quarter left (counterclockwise) or right from where it is.
	public func rotate(udid: String, clockwise: Bool) async throws {
		let current = try await deviceOrientation(udid: udid)
		_ = try await rotate(udid: udid, to: clockwise ? current.rotatedRight : current.rotatedLeft)
	}

	/// Sends the rotation and waits for the screen to settle; returns the interface rotation then.
	@discardableResult
	public func rotate(udid: String, to orientation: SimulatorDeviceOrientation) async throws -> SimulatorScreenRotation {
		let device = try ObjectBox(object: simDevice(udid: udid))
		try await Self.sendPurpleOrientation(orientation, to: device)

		// The interface property turns as the rotation animation starts; the animation takes about
		// 0.4 s more. An app that stays put never changes it, which the deadline covers.
		let target = orientation.screenRotation
		let clock = ContinuousClock()
		let deadline = clock.now + .milliseconds(1500)
		var rotation = try screenRotation(udid: udid)
		while rotation != target, clock.now < deadline {
			try await Task.sleep(for: .milliseconds(100))
			rotation = try screenRotation(udid: udid)
		}
		try await Task.sleep(for: .milliseconds(rotation == target ? 500 : 0))
		return try screenRotation(udid: udid)
	}

	/// A `GSEventTypeDeviceOrientationChanged` (50, host flag 0x20000) GSEvent as a raw Mach message
	/// to `PurpleWorkspacePort`: a 108-byte message, id 0x7B, the event type at 0x18, a 4-byte record
	/// size at 0x48 and the orientation at 0x4C — the layout idb's `SimulatorPurpleHID` documents.
	/// The send blocks while SpringBoard's queue is full, so it runs off the cooperative pool with a
	/// timeout.
	private static func sendPurpleOrientation(_ orientation: SimulatorDeviceOrientation, to device: ObjectBox) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			purpleQueue.async {
				var error: NSError?
				let port = ObjCRuntime.machPort(device.object, "lookup:error:", "PurpleWorkspacePort" as NSString, error: &error)
				guard port != MACH_PORT_NULL else {
					continuation.resume(throwing: SimulatorError.inputUnavailable(error?.localizedDescription ?? "PurpleWorkspacePort not found"))
					return
				}
				defer { mach_port_deallocate(mach_task_self_, port) }

				let message = Self.purpleMessage(event: 50 | 0x2_0000, value: orientation.purpleValue)
				var buffer = message
				let result = buffer.withUnsafeMutableBytes { bytes -> kern_return_t in
					let header = bytes.baseAddress!.assumingMemoryBound(to: mach_msg_header_t.self)
					header.pointee.msgh_remote_port = port
					return mach_msg(
						header,
						MACH_SEND_MSG | MACH_SEND_TIMEOUT,
						header.pointee.msgh_size,
						0,
						mach_port_t(MACH_PORT_NULL),
						2000,
						mach_port_t(MACH_PORT_NULL)
					)
				}
				if result == KERN_SUCCESS {
					continuation.resume()
				}
				else {
					continuation.resume(throwing: SimulatorError.inputUnavailable("rotation not delivered: \(String(cString: mach_error_string(result)))"))
				}
			}
		}
	}

	/// The Mach message for a GSEvent with a 4-byte payload; the remote port is filled in on send.
	static func purpleMessage(event: UInt32, value: UInt32) -> [UInt8] {
		var bytes = [UInt8](repeating: 0, count: 112)
		func write(_ word: UInt32, at offset: Int) {
			withUnsafeBytes(of: word.littleEndian) { source in
				for index in 0..<4 {
					bytes[offset + index] = source[index]
				}
			}
		}
		write(0x13, at: 0x00) // MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0)
		write(108, at: 0x04) // msgh_size
		write(0x7B, at: 0x14) // msgh_id
		write(event, at: 0x18)
		write(4, at: 0x48) // record_info_size
		write(value, at: 0x4C)
		return bytes
	}
}
