import CoreGraphics
import Foundation
import ObjectiveC

/// Typed `objc_msgSend` calls for the private classes this package talks to.
///
/// CoreSimulator ships no headers and SimulatorKit no Swift interface, so every call goes through
/// the runtime. Most of CoreSimulator's objects are `ROCKRemoteProxy`s forwarding to another
/// process, which answer `respondsToSelector:` but not key-value coding, so properties are read by
/// sending their getter rather than with `value(forKey:)`.
nonisolated enum ObjCRuntime {
	/// `RTLD_DEFAULT`, which the Swift overlay does not import.
	nonisolated(unsafe) static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

	/// `objc_msgSend`, for call shapes too specific to wrap here.
	static var messageSendFunction: UnsafeMutableRawPointer {
		messageSend
	}

	nonisolated(unsafe) private static let messageSend: UnsafeMutableRawPointer = {
		guard let symbol = dlsym(defaultHandle, "objc_msgSend") else {
			fatalError("objc_msgSend is missing from the process")
		}
		return symbol
	}()

	static func responds(_ target: AnyObject, to selector: String) -> Bool {
		target.responds(to: sel_registerName(selector))
	}

	/// Sends a message that returns an object (or nothing worth keeping).
	static func object(_ target: AnyObject, _ selector: String) -> AnyObject? {
		typealias Function = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector))?
			.takeUnretainedValue()
	}

	static func object(_ target: AnyObject, _ selector: String, _ argument: AnyObject?) -> AnyObject? {
		typealias Function = @convention(c) (AnyObject, Selector, AnyObject?) -> Unmanaged<AnyObject>?
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), argument)?
			.takeUnretainedValue()
	}

	/// Sends a `…:error:` message whose result is an object.
	static func object(
		_ target: AnyObject,
		_ selector: String,
		_ argument: AnyObject?,
		error: inout NSError?
	) -> AnyObject? {
		typealias Function = @convention(c) (
			AnyObject, Selector, AnyObject?, UnsafeMutablePointer<NSError?>
		) -> Unmanaged<AnyObject>?
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), argument, &error)?
			.takeUnretainedValue()
	}

	/// Sends an `…Error:` message with no other argument.
	static func object(_ target: AnyObject, _ selector: String, error: inout NSError?) -> AnyObject? {
		typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>) -> Unmanaged<AnyObject>?
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), &error)?
			.takeUnretainedValue()
	}

	/// Sends a message with one object argument that returns nothing. Never use `object(_:_:_:)`
	/// for a `void` method: Swift would retain whatever happens to be in the return register.
	static func send(_ target: AnyObject, _ selector: String, _ argument: AnyObject?) {
		typealias Function = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
		unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), argument)
	}

	static func setBool(_ target: AnyObject, _ selector: String, _ value: Bool) {
		typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
		unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), value)
	}

	static func unsignedInteger(_ target: AnyObject, _ selector: String) -> UInt {
		typealias Function = @convention(c) (AnyObject, Selector) -> UInt
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector))
	}

	static func float(_ target: AnyObject, _ selector: String) -> Float {
		typealias Function = @convention(c) (AnyObject, Selector) -> Float
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector))
	}

	/// Sends a message returning a `CGSize`. On arm64 a two-double struct comes back in registers,
	/// so plain `objc_msgSend` is the right entry point (there is no `_stret` variant to pick).
	static func size(_ target: AnyObject, _ selector: String) -> CGSize {
		typealias Function = @convention(c) (AnyObject, Selector) -> CGSize
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector))
	}

	/// `-[SimDevice lookup:error:]`: a send right to a Mach service in the simulator's bootstrap
	/// namespace, or `MACH_PORT_NULL`.
	static func machPort(
		_ target: AnyObject,
		_ selector: String,
		_ argument: AnyObject,
		error: inout NSError?
	) -> mach_port_t {
		typealias Function = @convention(c) (AnyObject, Selector, AnyObject, UnsafeMutablePointer<NSError?>) -> mach_port_t
		return unsafeBitCast(messageSend, to: Function.self)(target, sel_registerName(selector), argument, &error)
	}

	/// `-[SimScreen registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:]`.
	static func registerScreenCallbacks(
		on screen: AnyObject,
		token: UUID,
		queue: DispatchQueue,
		frame: @escaping @convention(block) () -> Void,
		surfacesChanged: @escaping @convention(block) (AnyObject?, AnyObject?) -> Void,
		propertiesChanged: @escaping @convention(block) (AnyObject?) -> Void
	) {
		typealias Function = @convention(c) (
			AnyObject,
			Selector,
			NSUUID,
			DispatchQueue,
			@convention(block) () -> Void,
			@convention(block) (AnyObject?, AnyObject?) -> Void,
			@convention(block) (AnyObject?) -> Void
		) -> Void
		unsafeBitCast(messageSend, to: Function.self)(
			screen,
			sel_registerName(
				"registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:"
			),
			token as NSUUID,
			queue,
			frame,
			surfacesChanged,
			propertiesChanged
		)
	}
}

/// Carries a CoreSimulator object across isolation boundaries. Its objects are XPC proxies that
/// may be messaged from any thread, which the compiler cannot know.
nonisolated struct ObjectBox: @unchecked Sendable {
	let object: AnyObject
}
