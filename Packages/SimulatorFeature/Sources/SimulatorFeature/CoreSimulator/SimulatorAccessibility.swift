import AppKit
import Foundation
import os

/// One element of a simulator app's accessibility tree, frames in screen points.
public struct SimulatorAccessibilityNode: Equatable, Sendable {
	/// The role without its "AX" prefix: "Button", "StaticText", "Application".
	public var role: String
	public var label: String?
	public var value: String?
	public var identifier: String?
	public var frame: CGRect
	public var isEnabled: Bool
	public var children: [SimulatorAccessibilityNode]

	/// Where a finger activates the element. The centre, except for a switch drawn at the trailing
	/// end of a wide row: iOS reports a `UISwitch` (and a SwiftUI `Toggle`) with its whole row's
	/// frame, and a tap on the row's centre does nothing (checked in Settings, 2026-10-08). AXe
	/// found the same and taps 31 pt in from the trailing edge of a switch wider than 100 pt.
	public var activationPoint: CGPoint {
		guard role == "Switch", frame.width > 100 else {
			return CGPoint(x: frame.midX, y: frame.midY)
		}
		return CGPoint(x: frame.maxX - 31, y: frame.midY)
	}

	public init(
		role: String,
		label: String? = nil,
		value: String? = nil,
		identifier: String? = nil,
		frame: CGRect,
		isEnabled: Bool = true,
		children: [SimulatorAccessibilityNode] = []
	) {
		self.role = role
		self.label = label
		self.value = value
		self.identifier = identifier
		self.frame = frame
		self.isEnabled = isEnabled
		self.children = children
	}
}

/// Reads a booted simulator's accessibility tree through Apple's private
/// AccessibilityPlatformTranslation framework — what Xcode's Accessibility Inspector uses.
///
/// `AXPTranslator` turns the guest's accessibility objects into `NSAccessibilityElement`s
/// (`AXPMacPlatformElement`) whose ordinary accessors (`accessibilityLabel()`, `…Frame()`,
/// `…Children()`) are answered lazily: each one makes the translator call back into its bridge
/// delegate for a request, which is sent into the simulator with
/// `-[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]`. The translator
/// wants that answer synchronously, so the delegate blocks (bounded) on the asynchronous reply.
/// Requests carry a token — the device's UDID — which the delegate maps back to the device.
///
/// The translator is a process-wide singleton that is not thread-safe, so every touch of it and of
/// its elements runs on one serial queue — also keeping those blocking waits off the cooperative
/// pool. The approach and the selectors follow Meta's idb (`FBSimulatorAX`, MIT).
final class SimulatorAccessibility: @unchecked Sendable {
	static let shared = SimulatorAccessibility()

	/// Bounds a walk of a pathological tree; each attribute read is an XPC round trip.
	static let maximumNodes = 1500
	static let maximumDepth = 40

	private let workQueue = DispatchQueue(label: "com.bridgecommander.simulator.accessibility")
	private let delegate = AccessibilityBridgeDelegate()
	/// Set up on `workQueue` on first use.
	private var translator: AnyObject?

	private init() {}

	/// The frontmost application's tree (SpringBoard's on the home screen).
	func frontmostTree(device: ObjectBox) async throws -> SimulatorAccessibilityNode {
		try await withFrontmostApplication(device: device) { element in
			var budget = Self.maximumNodes
			return Self.read(element, depth: 0, budget: &budget)
		}
	}

	/// Runs `body` on the work queue with the frontmost application's live element, for work that
	/// reads or acts on elements rather than on a copied tree.
	func withFrontmostApplication<T: Sendable>(
		device: ObjectBox,
		_ body: @escaping @Sendable (NSAccessibilityElement) throws -> T
	) async throws -> T {
		try await perform { [self] translator in
			try withToken(device: device) { token in
				typealias Frontmost = @convention(c) (AnyObject, Selector, UInt32, NSString) -> Unmanaged<AnyObject>?
				let translation = unsafeBitCast(ObjCRuntime.messageSendFunction, to: Frontmost.self)(
					translator,
					sel_registerName("frontmostApplicationWithDisplayId:bridgeDelegateToken:"),
					0,
					token as NSString
				)?.takeUnretainedValue()
				guard let element = platformElement(translation, token: token, translator: translator) else {
					throw SimulatorError.accessibilityUnavailable("no frontmost application; the simulator may still be starting up")
				}
				return try body(element)
			}
		}
	}

	/// The element at a point in screen points, with its descendants.
	func element(at point: CGPoint, device: ObjectBox) async throws -> SimulatorAccessibilityNode? {
		try await perform { [self] translator in
			try withToken(device: device) { token in
				typealias ObjectAtPoint = @convention(c) (AnyObject, Selector, CGPoint, UInt32, NSString) -> Unmanaged<AnyObject>?
				let translation = unsafeBitCast(ObjCRuntime.messageSendFunction, to: ObjectAtPoint.self)(
					translator,
					sel_registerName("objectAtPoint:displayId:bridgeDelegateToken:"),
					point,
					0,
					token as NSString
				)?.takeUnretainedValue()
				guard let element = platformElement(translation, token: token, translator: translator) else {
					return nil
				}
				var budget = 200
				return Self.read(element, depth: 0, budget: &budget)
			}
		}
	}

	// MARK: - Translator

	private func perform<T: Sendable>(_ work: @escaping @Sendable (AnyObject) throws -> T) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			workQueue.async { [self] in
				do {
					continuation.resume(returning: try work(loadTranslator()))
				}
				catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	/// On `workQueue` only.
	private func loadTranslator() throws -> AnyObject {
		if let translator {
			return translator
		}

		let path = "/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation"
		guard
			dlopen(path, RTLD_NOW) != nil,
			let translatorClass = NSClassFromString("AXPTranslator"),
			let shared = ObjCRuntime.object(translatorClass, "sharedInstance")
		else {
			throw SimulatorError.accessibilityUnavailable("AccessibilityPlatformTranslation could not be loaded")
		}

		// Some translator paths check the protocol rather than individual selectors.
		if let protocolHandle = objc_getProtocol("AXPTranslationTokenDelegateHelper") {
			class_addProtocol(AccessibilityBridgeDelegate.self, protocolHandle)
		}
		ObjCRuntime.send(shared, "setBridgeTokenDelegate:", delegate)
		ObjCRuntime.setBool(shared, "setSupportsDelegateTokens:", true)
		ObjCRuntime.setBool(shared, "setAccessibilityEnabled:", true)
		translator = shared
		return shared
	}

	private func withToken<T>(device: ObjectBox, _ body: (String) throws -> T) throws -> T {
		guard ObjCRuntime.responds(device.object, to: "sendAccessibilityRequestAsync:completionQueue:completionHandler:") else {
			throw SimulatorError.accessibilityUnavailable("this CoreSimulator has no accessibility requests")
		}
		// One token per device, kept for good: the translator caches the elements it hands out,
		// tagged with the token of the request that first produced them, and keeps asking for that
		// token when they are read again later. A per-request token that is dropped afterwards left
		// every read after the first with an empty tree.
		let token = (ObjCRuntime.object(device.object, "UDID") as? NSUUID)?.uuidString ?? UUID().uuidString
		delegate.register(token: token, device: device)
		return try body(token)
	}

	/// The translation as an `NSAccessibilityElement`, both carrying the token so their lazy
	/// attribute reads reach the right device.
	private func platformElement(_ translation: AnyObject?, token: String, translator: AnyObject) -> NSAccessibilityElement? {
		guard let translation else {
			return nil
		}
		ObjCRuntime.send(translation, "setBridgeDelegateToken:", token as NSString)
		guard let element = ObjCRuntime.object(translator, "macPlatformElementFromTranslation:", translation) as? NSAccessibilityElement else {
			return nil
		}
		if let elementTranslation = ObjCRuntime.object(element, "translation") {
			ObjCRuntime.send(elementTranslation, "setBridgeDelegateToken:", token as NSString)
		}
		return element
	}

	private static func read(_ element: NSAccessibilityElement, depth: Int, budget: inout Int) -> SimulatorAccessibilityNode {
		budget -= 1
		var node = attributes(of: element)

		guard depth < maximumDepth else {
			return node
		}
		for child in element.accessibilityChildren() ?? [] {
			guard budget > 0 else {
				break
			}
			if let child = child as? NSAccessibilityElement {
				node.children.append(read(child, depth: depth + 1, budget: &budget))
			}
		}
		return node
	}

	/// One element's own attributes, without its children. On `workQueue` only.
	static func attributes(of element: NSAccessibilityElement) -> SimulatorAccessibilityNode {
		var role = element.accessibilityRole()?.rawValue ?? "Element"
		if role.hasPrefix("AX") {
			role.removeFirst(2)
		}
		if role == "CheckBox", isSwitch(element) {
			role = "Switch"
		}
		return SimulatorAccessibilityNode(
			role: role,
			label: nonEmpty(element.accessibilityLabel()),
			value: nonEmpty(describe(element.accessibilityValue())),
			identifier: nonEmpty(element.accessibilityIdentifier()),
			frame: element.accessibilityFrame(),
			isEnabled: element.isAccessibilityEnabled()
		)
	}

	/// The translator turns a `UISwitch` or SwiftUI `Toggle` into a macOS checkbox; its subrole
	/// (`AXSwitch`) or role description still says what it is.
	private static func isSwitch(_ element: NSAccessibilityElement) -> Bool {
		if element.accessibilitySubrole() == .switch {
			return true
		}
		let description = element.accessibilityRoleDescription()?.lowercased() ?? ""
		return description.contains("switch") || description.contains("toggle")
	}

	private static func describe(_ value: Any?) -> String? {
		switch value {
		case let string as String:
			string
		case let attributed as NSAttributedString:
			attributed.string
		case let number as NSNumber:
			number.stringValue
		default:
			nil
		}
	}

	private static func nonEmpty(_ string: String?) -> String? {
		guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return nil
		}
		return string
	}
}

/// `AXPTranslator`'s bridge delegate (`AXPTranslationTokenDelegateHelper`): answers each attribute
/// request by sending it into the simulator the token names and waiting for the reply.
final class AccessibilityBridgeDelegate: NSObject, @unchecked Sendable {
	/// A stalled accessibility service must not hang the walk; an empty answer reads as "no value".
	private static let requestTimeout: DispatchTimeInterval = .seconds(5)

	private let devices = OSAllocatedUnfairLock<[String: ObjectBox]>(initialState: [:])
	private let callbackQueue = DispatchQueue(label: "com.bridgecommander.simulator.accessibility.callback")

	func register(token: String, device: ObjectBox) {
		devices.withLock { $0[token] = device }
	}

	@objc(accessibilityTranslationDelegateBridgeCallbackWithToken:)
	func bridgeCallback(token: NSString) -> @convention(block) (AnyObject?) -> AnyObject? {
		let key = token as String
		let device = devices.withLock { $0[key] }
		let callbackQueue = callbackQueue
		return { request in
			guard let device, let request else {
				return nil
			}
			return Self.send(request, to: device.object, queue: callbackQueue)
		}
	}

	@objc(accessibilityTranslationConvertPlatformFrameToSystem:withToken:)
	func convertPlatformFrame(_ rect: CGRect, token: NSString) -> CGRect {
		rect
	}

	@objc(accessibilityTranslationRootParentWithToken:)
	func rootParent(token: NSString) -> AnyObject? {
		nil
	}

	private static func send(_ request: AnyObject, to device: AnyObject, queue: DispatchQueue) -> AnyObject? {
		final class Box: @unchecked Sendable {
			var response: AnyObject?
		}

		typealias Send = @convention(c) (
			AnyObject, Selector, AnyObject, DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void
		) -> Void
		let box = Box()
		let group = DispatchGroup()
		group.enter()
		let completion: @convention(block) (AnyObject?) -> Void = { response in
			box.response = response
			group.leave()
		}
		unsafeBitCast(ObjCRuntime.messageSendFunction, to: Send.self)(
			device,
			sel_registerName("sendAccessibilityRequestAsync:completionQueue:completionHandler:"),
			request,
			queue,
			completion
		)
		guard group.wait(timeout: .now() + requestTimeout) == .success else {
			return nil
		}
		return box.response
	}
}
