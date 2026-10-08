import Foundation
import os
import XPC

/// A hardware button, by its HID Consumer-page usage.
///
/// There is no Apple Pay button: `dtuhidd` has no usage for it, and two side-button presses lock
/// and wake the device rather than bringing up Wallet (idb, `SimulatorHIDButtonIdentity`). Only the
/// legacy Indigo path, which these runtimes ignore, had a source for it.
public enum SimulatorHardwareButton: String, CaseIterable, Sendable {
	case home
	case lock
	/// The same physical button as `lock`, so the same usage; named for the models and people who
	/// look for it by this name on Face ID iPhones.
	case sideButton = "side_button"
	case siri
	case volumeUp = "volume_up"
	case volumeDown = "volume_down"
	case playPause = "play_pause"

	var consumerUsage: UInt64 {
		switch self {
		case .home:
			0x40 // Menu
		case .lock, .sideButton:
			0x30 // Power
		case .siri:
			0xCF // Voice Command
		case .volumeUp:
			0xE9
		case .volumeDown:
			0xEA
		case .playPause:
			0xCD
		}
	}

	/// The name the pane's menu shows.
	public var title: String {
		switch self {
		case .home:
			"Home"
		case .lock:
			"Lock"
		case .sideButton:
			"Side Button"
		case .siri:
			"Siri"
		case .volumeUp:
			"Volume Up"
		case .volumeDown:
			"Volume Down"
		case .playPause:
			"Play/Pause"
		}
	}
}

/// The phase of a digitizer contact, as `dtuhidd` numbers it.
enum SimulatorTouchPhase: UInt64 {
	case began = 0
	case moved = 1
	case ended = 2
}

/// One XPC connection to `dtuhidd`'s digitizer service inside a booted simulator.
///
/// From CoreSimulator 1155.4 (Xcode 27) the guest drops the legacy Indigo HID messages that
/// `SimDeviceLegacyHIDClient` sends — they are delivered and silently discarded — so touches,
/// buttons and keys go to `dtuhidd` instead, as plain XPC dictionaries. The service is looked up in
/// the simulator's bootstrap namespace (`-[SimDevice lookup:error:]`), wrapped by the private
/// `xpc_endpoint_create_mach_port_4sim`, and the connection marked simulator-to-host, without which
/// the daemon sees the peer but never a payload. Wire format and the liveness dance follow Meta's
/// idb (`SimulatorDTUHIDConnection`, MIT).
final class SimulatorHIDConnection: @unchecked Sendable {
	static let digitizerService = "com.apple.coredevice.feature.remote.hid.digitizer"
	/// Vendor-defined HID reports: what folds an iPhone Duo (`SimulatorFold`).
	static let vendorDefinedService = "com.apple.coredevice.feature.remote.hid.vendordefined"

	private let connection: xpc_connection_t
	private let service: String
	private let isInvalidated = OSAllocatedUnfairLock(initialState: false)

	var isUsable: Bool {
		!isInvalidated.withLock { $0 }
	}

	private init(connection: xpc_connection_t, service: String = digitizerService) {
		self.connection = connection
		self.service = service
		xpc_connection_set_target_queue(connection, DispatchQueue(label: "com.bridgecommander.simulator.hid"))
		xpc_connection_set_event_handler(connection) { [isInvalidated] event in
			if xpc_get_type(event) == XPC_TYPE_ERROR, event === XPC_ERROR_CONNECTION_INVALID {
				isInvalidated.withLock { $0 = true }
			}
		}
		xpc_connection_resume(connection)
	}

	deinit {
		xpc_connection_cancel(connection)
	}

	/// Connects to `dtuhidd` in `device` and waits until the daemon answers.
	///
	/// The lookup succeeds whether or not the demand-launched daemon can run — early in a boot it
	/// aborts until a display is up, and launchd then throttles its respawn — and a send to a dead
	/// daemon reports no error. So a barrier is round-tripped, and retried with a back-off the way
	/// idb does, before the connection is handed out.
	static func connect(to device: AnyObject) async throws -> SimulatorHIDConnection {
		var lastError: Error?
		for attempt in 1...4 {
			do {
				let connection = try SimulatorHIDConnection(connection: makeConnection(device: device))
				try await connection.confirmLiveness()
				return connection
			}
			catch {
				lastError = error
				if attempt < 4 {
					try await Task.sleep(for: .seconds(2))
				}
			}
		}
		throw SimulatorError.inputUnavailable(lastError?.localizedDescription ?? "no answer")
	}

	/// A connection, not yet resumed, to a `dtuhidd`-style service in `device`'s bootstrap
	/// namespace. Also used for the guest's orientation service, which speaks the same envelope.
	static func makeConnection(device: AnyObject, service: String = digitizerService) throws -> xpc_connection_t {
		typealias EndpointFromPort = @convention(c) (mach_port_t, UInt64, UInt64) -> Unmanaged<AnyObject>?
		typealias ConnectionFromEndpoint = @convention(c) (xpc_object_t) -> Unmanaged<AnyObject>?
		typealias EnableSimToHost = @convention(c) (xpc_connection_t) -> Void

		guard
			let endpointSymbol = dlsym(ObjCRuntime.defaultHandle, "xpc_endpoint_create_mach_port_4sim"),
			let connectionSymbol = dlsym(ObjCRuntime.defaultHandle, "xpc_connection_create_from_endpoint"),
			let simToHostSymbol = dlsym(ObjCRuntime.defaultHandle, "xpc_connection_enable_sim2host_4sim")
		else {
			throw SimulatorError.inputUnavailable("libxpc has no simulator endpoint support")
		}

		var error: NSError?
		let port = ObjCRuntime.machPort(device, "lookup:error:", service as NSString, error: &error)
		guard port != MACH_PORT_NULL else {
			throw SimulatorError.inputUnavailable(error?.localizedDescription ?? "\(service) not found")
		}

		// Both create functions return +1; the endpoint takes over the lookup's send right.
		guard
			let endpoint = unsafeBitCast(endpointSymbol, to: EndpointFromPort.self)(port, 0, 0)?
			.takeRetainedValue() as? xpc_object_t,
			let connection = unsafeBitCast(connectionSymbol, to: ConnectionFromEndpoint.self)(endpoint)?
			.takeRetainedValue() as? xpc_connection_t
		else {
			throw SimulatorError.inputUnavailable("could not connect to \(service)")
		}
		unsafeBitCast(simToHostSymbol, to: EnableSimToHost.self)(connection)
		return connection
	}

	/// A barrier carrying keyboard usage 0 ("no event"), so the daemon answers without the guest
	/// seeing a key.
	private func confirmLiveness() async throws {
		let message = message(type: "IndigoKeyboardButtonEvent", payload: Self.keyPayload(usage: 0, isDown: false), isBarrier: true)
		guard await roundTrip(message) == .answered else {
			xpc_connection_cancel(connection)
			throw SimulatorError.inputUnavailable("dtuhidd did not answer")
		}
		// The first reply means the daemon is up; it still needs a moment to open its devices.
		try await Task.sleep(for: .milliseconds(200))
	}

	private enum RoundTrip {
		case answered
		/// The reply was an XPC error: the daemon is not running, or dropped the connection.
		case failed
		/// No reply in time: the daemon is up but busy.
		case timedOut
	}

	/// Sends `message`, a barrier, and waits up to `timeout` for the daemon's reply. A barrier is
	/// answered once everything sent before it has been handled, and is not itself dispatched.
	private func roundTrip(_ message: xpc_object_t, timeout: TimeInterval = 4) async -> RoundTrip {
		await withCheckedContinuation { continuation in
			let once = OSAllocatedUnfairLock(initialState: false)
			let resume: @Sendable (RoundTrip) -> Void = { value in
				let first = once.withLock { done in
					defer { done = true }
					return !done
				}
				if first {
					continuation.resume(returning: value)
				}
			}
			xpc_connection_send_message_with_reply(connection, message, nil) { reply in
				resume(xpc_get_type(reply) == XPC_TYPE_DICTIONARY ? .answered : .failed)
			}
			DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
				resume(.timedOut)
			}
		}
	}

	// MARK: - Sending

	/// A single-finger contact, or two fingers when `second` is given (a pinch, a rotation, a
	/// two-finger drag): `dtuhidd` takes the second contact as `pointTwo` of the same event. Points
	/// are normalized, top-left origin. A gesture keeps one finger count from began to ended.
	/// `target` is the screen touched: 0 for the main one, else a screen ID (an unfolded iPhone
	/// Duo's inner panel, 3), which the main-screen target does not reach.
	func touch(_ point: CGPoint, _ second: CGPoint? = nil, phase: SimulatorTouchPhase, target: UInt32 = 0) {
		let payload = xpc_dictionary_create(nil, nil, 0)
		for (key, contactPoint) in [("pointOne", point), ("pointTwo", second)] {
			guard let contactPoint else {
				continue
			}
			let contact = xpc_dictionary_create(nil, nil, 0)
			xpc_dictionary_set_double(contact, "x", contactPoint.x)
			xpc_dictionary_set_double(contact, "y", contactPoint.y)
			xpc_dictionary_set_value(payload, key, contact)
		}
		xpc_dictionary_set_uint64(payload, "eventType", phase.rawValue)
		xpc_dictionary_set_uint64(payload, "edge", 0)
		xpc_dictionary_set_uint64(payload, "target", UInt64(target))
		send(type: "IndigoDigitizerEvent", payload: payload)
	}

	func key(usage: UInt64, isDown: Bool) {
		send(type: "IndigoKeyboardButtonEvent", payload: Self.keyPayload(usage: usage, isDown: isDown))
	}

	func button(_ button: SimulatorHardwareButton, isDown: Bool) {
		let payload = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_uint64(payload, "usagePage", 0x0C)
		xpc_dictionary_set_uint64(payload, "usageCode", button.consumerUsage)
		xpc_dictionary_set_uint64(payload, "state", isDown ? 1 : 2)
		send(type: "IndigoButtonEvent", payload: payload)
	}

	private func send(type: String, payload: xpc_object_t) {
		xpc_connection_send_message(connection, message(type: type, payload: payload, isBarrier: false))
	}

	/// How long a vendor-defined report's barrier is waited for before giving up.
	private static let vendorDefinedPatience: TimeInterval = 30

	/// A connection to `dtuhidd`'s vendor-defined service in `device`, for `sendVendorDefinedReport`.
	/// Kept for the device's life (`SimulatorHost.sendDeviceState`) rather than made per report: the
	/// daemon builds a whole set of virtual HID services (buttons, keyboard, the touchscreens) for
	/// every connection, one connection at a time, which takes 0.5 s at best and once took 13 s
	/// while the guest was busy after a fold (checked live, 2026-10-08); a rotation and a fold sent
	/// in a row on connections of their own queued behind each other, and reports were lost.
	static func vendorDefined(device: AnyObject) throws -> SimulatorHIDConnection {
		try SimulatorHIDConnection(
			connection: makeConnection(device: device, service: vendorDefinedService),
			service: vendorDefinedService
		)
	}

	/// What sending a vendor-defined report came to.
	enum VendorDefinedResult {
		case delivered
		/// An XPC error: the daemon is not running (yet), or dropped the connection. A new
		/// connection may do.
		case failed
		/// No answer within `vendorDefinedPatience`: the daemon is up but stuck.
		case timedOut
	}

	/// Sends one vendor-defined HID report on this connection and returns once the daemon has
	/// handled it. The report has to go as a plain message — sent as the barrier itself it is
	/// answered but never dispatched — so a barrier before it confirms the daemon is up (a report
	/// sent while it is still starting would be lost) and one after it that it was handled. The
	/// guest keeps what a report set (the hinge angle, the orientation) for good, but reads it
	/// from the connection's virtual device a little later: a report on a connection closed as
	/// soon as its barrier was answered was lost every time (checked live, 2026-10-08), one reason
	/// the connection is kept.
	func sendVendorDefinedReport(usagePage: UInt64, usage: UInt64, data: Data, isNewConnection: Bool) async throws -> VendorDefinedResult {
		let payload = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_uint64(payload, "usagePage", usagePage)
		xpc_dictionary_set_uint64(payload, "usage", usage)
		xpc_dictionary_set_uint64(payload, "version", 0)
		data.withUnsafeBytes { bytes in
			xpc_dictionary_set_data(payload, "data", bytes.baseAddress!, bytes.count)
		}
		let type = "IndigoVendorDefinedEvent"
		let barrier = message(type: type, payload: payload, isBarrier: true)

		var result = await roundTrip(barrier, timeout: Self.vendorDefinedPatience)
		guard result == .answered else {
			return result == .failed ? .failed : .timedOut
		}
		if isNewConnection {
			// The first reply means the daemon is up; it still needs a moment to open its devices.
			try await Task.sleep(for: .milliseconds(200))
		}
		send(type: type, payload: payload)
		result = await roundTrip(barrier, timeout: Self.vendorDefinedPatience)
		switch result {
		case .answered:
			return .delivered
		case .failed:
			return .failed
		case .timedOut:
			return .timedOut
		}
	}

	/// `HIDButtonState` is 1-based: down is 1, up is 2 (0 is rejected by the daemon's decoder).
	private static func keyPayload(usage: UInt64, isDown: Bool) -> xpc_object_t {
		let payload = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_uint64(payload, "usageCode", usage)
		xpc_dictionary_set_uint64(payload, "state", isDown ? 1 : 2)
		return payload
	}

	private func message(type: String, payload: xpc_object_t, isBarrier: Bool) -> xpc_object_t {
		let message = xpc_dictionary_create(nil, nil, 0)
		xpc_dictionary_set_string(message, "messageType", type)
		xpc_dictionary_set_bool(message, "isBarrier", isBarrier)
		xpc_dictionary_set_string(message, "featureIdentifier", service)
		xpc_dictionary_set_value(message, "payload", payload)
		return message
	}
}
