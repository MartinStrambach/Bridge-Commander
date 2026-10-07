import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import IOSurface
import os
import UniformTypeIdentifiers

/// The app's one connection to CoreSimulator: the device list, each device's screen, and input.
///
/// CoreSimulator is loaded into this process — the way Simulator.app uses it — rather than into a
/// helper, so the pane can hand the simulator's own framebuffer `IOSurface` to a layer with no
/// copy or encode. Its objects are XPC proxies that are safe to message from any thread; the
/// little mutable state here sits behind a lock.
public final class SimulatorHost: @unchecked Sendable {
	public static let shared = SimulatorHost()

	/// The device chosen last, anywhere: what a repository with no choice of its own starts on,
	/// and what a `claude` outside the app acts on when not told otherwise.
	private static let selectedDeviceKey = "simulatorSelectedDeviceUDID"
	/// Each repository's (worktree's) own device, so one terminal can work on an iPhone while
	/// another works on an iPad.
	private static let repositorySelectionsKey = "simulatorSelectedDeviceUDIDByRepository"

	private struct State {
		var deviceSet: ObjectBox?
		var hidConnections: [String: SimulatorHIDConnection] = [:]
		var pendingConnections: [String: Task<SimulatorHIDConnection, Error>] = [:]
	}

	private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())
	private let ciContext = CIContext(options: [.cacheIntermediates: false])

	private init() {}

	// MARK: - Loading

	/// The selected Xcode's developer directory, the one `xcrun` would use.
	private static let developerDirectory: String = {
		if let configured = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !configured.isEmpty {
			return configured
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
		process.arguments = ["-p"]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			process.waitUntilExit()
			let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
			if process.terminationStatus == 0, !path.isEmpty {
				return path
			}
		}
		catch {}
		return "/Applications/Xcode.app/Contents/Developer"
	}()

	private static let frameworkLoad: Result<Void, SimulatorError> = {
		let path = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
		guard dlopen(path, RTLD_NOW | RTLD_GLOBAL) != nil else {
			let detail = dlerror().map { String(cString: $0) } ?? path
			return .failure(.frameworkUnavailable(detail))
		}
		return .success(())
	}()

	/// The loaded CoreSimulator's version, e.g. "1171.7". Gates the input transport, which changed
	/// in 1155.4 (see `SimulatorHIDConnection`).
	public static var coreSimulatorVersion: String? {
		guard case .success = frameworkLoad, let simDevice = NSClassFromString("SimDevice") else {
			return nil
		}
		return Bundle(for: simDevice).infoDictionary?["CFBundleVersion"] as? String
	}

	private func deviceSet() throws -> AnyObject {
		if let existing = state.withLock({ $0.deviceSet }) {
			return existing.object
		}
		try Self.frameworkLoad.get()

		guard let contextClass = NSClassFromString("SimServiceContext") else {
			throw SimulatorError.frameworkUnavailable("SimServiceContext is missing")
		}
		var error: NSError?
		guard
			let context = ObjCRuntime.object(
				contextClass,
				"sharedServiceContextForDeveloperDir:error:",
				Self.developerDirectory as NSString,
				error: &error
			)
		else {
			throw SimulatorError.frameworkUnavailable(error?.localizedDescription ?? "no service context")
		}
		guard let set = ObjCRuntime.object(context, "defaultDeviceSetWithError:", error: &error) else {
			throw SimulatorError.frameworkUnavailable(error?.localizedDescription ?? "no device set")
		}
		let box = ObjectBox(object: set)
		state.withLock { $0.deviceSet = box }
		return set
	}

	// MARK: - Devices

	/// The iOS and iPadOS simulators whose runtime is installed, booted ones first.
	public func devices() throws -> [SimulatorDevice] {
		let set = try deviceSet()
		let simDevices = ObjCRuntime.object(set, "devices") as? [AnyObject] ?? []
		return simDevices
			.compactMap(Self.describe)
			.sorted { lhs, rhs in
				if lhs.isBooted != rhs.isBooted {
					return lhs.isBooted
				}
				if lhs.runtimeName != rhs.runtimeName {
					return lhs.runtimeName.compare(rhs.runtimeName, options: .numeric) == .orderedDescending
				}
				return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
			}
	}

	private static func describe(_ device: AnyObject) -> SimulatorDevice? {
		guard
			let udid = ObjCRuntime.object(device, "UDID") as? NSUUID,
			let name = ObjCRuntime.object(device, "name") as? String,
			let runtime = ObjCRuntime.object(device, "runtime"),
			let runtimeName = ObjCRuntime.object(runtime, "name") as? String,
			runtimeName.hasPrefix("iOS"),
			let deviceType = ObjCRuntime.object(device, "deviceType")
		else {
			return nil
		}

		let state = SimulatorDevice.State(rawValue: ObjCRuntime.unsignedInteger(device, "state"))
		return SimulatorDevice(
			id: udid.uuidString,
			name: name,
			runtimeName: runtimeName,
			state: state,
			screenPixelSize: ObjCRuntime.size(deviceType, "mainScreenSize"),
			screenScale: CGFloat(ObjCRuntime.float(deviceType, "mainScreenScale")),
			rotation: state == .booted ? (try? mainScreen(of: device)).map(screenRotation(of:)) ?? .upright : .upright
		)
	}

	func simDevice(udid: String) throws -> AnyObject {
		let set = try deviceSet()
		let simDevices = ObjCRuntime.object(set, "devices") as? [AnyObject] ?? []
		guard
			let device = simDevices.first(where: {
				(ObjCRuntime.object($0, "UDID") as? NSUUID)?.uuidString.caseInsensitiveCompare(udid) == .orderedSame
			})
		else {
			throw SimulatorError.deviceNotFound(udid)
		}
		return device
	}

	private var lastSelectedDeviceId: String? {
		UserDefaults.standard.string(forKey: Self.selectedDeviceKey)
	}

	private var repositorySelections: [String: String] {
		UserDefaults.standard.dictionary(forKey: Self.repositorySelectionsKey) as? [String: String] ?? [:]
	}

	/// The device `repositoryPath`'s pane shows and its terminal's tools act on: its own choice,
	/// else the last one made anywhere. `nil` (a `claude` outside the app) gets the last one.
	public func selectedDeviceId(repositoryPath: String?) -> String? {
		state.withLock { _ in
			repositoryPath.flatMap { repositorySelections[$0] } ?? lastSelectedDeviceId
		}
	}

	/// Makes `deviceId` `repositoryPath`'s device, and the last one chosen.
	public func select(deviceId: String, repositoryPath: String?) {
		// Under the lock so the pane and a tool call choosing at once do not drop each other's
		// entry from the dictionary.
		state.withLock { _ in
			if let repositoryPath {
				var selections = repositorySelections
				selections[repositoryPath] = deviceId
				UserDefaults.standard.set(selections, forKey: Self.repositorySelectionsKey)
			}
			UserDefaults.standard.set(deviceId, forKey: Self.selectedDeviceKey)
		}
	}

	/// The device a command from `repositoryPath`'s terminal addresses: `udid` when given,
	/// otherwise the repository's device if it is booted, otherwise a booted one — preferably one
	/// no other repository has chosen, so a worktree whose iPad is shut down does not take over
	/// another worktree's iPhone. That one then becomes the repository's device, so the pane
	/// follows the simulator Claude booted.
	public func resolveDevice(udid: String?, repositoryPath: String?) throws -> SimulatorDevice {
		let all = try devices()
		if let udid {
			guard let device = all.first(where: { $0.id.caseInsensitiveCompare(udid) == .orderedSame }) else {
				throw SimulatorError.deviceNotFound(udid)
			}
			guard device.isBooted else {
				throw SimulatorError.deviceNotBooted(device.name)
			}
			return device
		}

		if
			let selected = selectedDeviceId(repositoryPath: repositoryPath),
			let device = all.first(where: { $0.id == selected }),
			device.isBooted
		{
			return device
		}
		let takenByOthers = Set(repositorySelections.filter { $0.key != repositoryPath }.values)
		guard
			let booted = all.first(where: { $0.isBooted && !takenByOthers.contains($0.id) })
				?? all.first(where: \.isBooted)
		else {
			throw SimulatorError.noBootedDevice
		}
		select(deviceId: booted.id, repositoryPath: repositoryPath)
		return booted
	}

	// MARK: - Screen

	/// The main display's port descriptor: the `SimScreen` whose size is the device type's main
	/// screen. A device also lists screens for external displays and CarPlay.
	func mainScreen(udid: String) throws -> AnyObject {
		try Self.mainScreen(of: simDevice(udid: udid))
	}

	static func mainScreen(of device: AnyObject) throws -> AnyObject {
		guard
			let deviceType = ObjCRuntime.object(device, "deviceType"),
			let io = ObjCRuntime.object(device, "io"),
			let ports = ObjCRuntime.object(io, "ioPorts") as? [AnyObject]
		else {
			throw SimulatorError.noFramebuffer
		}

		let mainSize = ObjCRuntime.size(deviceType, "mainScreenSize")
		var largest: (screen: AnyObject, area: CGFloat)?
		for port in ports {
			guard
				let descriptor = ObjCRuntime.object(port, "descriptor"),
				ObjCRuntime.responds(descriptor, to: "framebufferSurface"),
				ObjCRuntime.responds(descriptor, to: "displaySize")
			else {
				continue
			}

			let size = ObjCRuntime.size(descriptor, "displaySize")
			if size == mainSize {
				return descriptor
			}
			let area = size.width * size.height
			if area > (largest?.area ?? 0) {
				largest = (descriptor, area)
			}
		}
		guard let largest else {
			throw SimulatorError.noFramebuffer
		}
		return largest.screen
	}

	/// The screen as it is now, at its native pixel size, portrait (the framebuffer is, whatever
	/// the rotation).
	public func screenImage(udid: String) throws -> CGImage {
		try framebufferImage(screen: mainScreen(udid: udid), orientation: .up)
	}

	private func framebufferImage(screen: AnyObject, orientation: CGImagePropertyOrientation) throws -> CGImage {
		guard let surface = ObjCRuntime.object(screen, "framebufferSurface") else {
			throw SimulatorError.noFramebuffer
		}

		let image = CIImage(ioSurface: unsafeDowncast(surface, to: IOSurfaceRef.self)).oriented(orientation)
		guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
			throw SimulatorError.noFramebuffer
		}
		return cgImage
	}

	/// A JPEG of the screen scaled to points and turned the way the interface is, so a pixel in it
	/// is a point the tools take. The rotation is read with the frame rather than taken from
	/// `device`, so the image is the right way up even if the device turned since it was read.
	public func screenshotJPEG(device: SimulatorDevice, quality: Double = 0.8) throws -> Data {
		let screen = try mainScreen(udid: device.id)
		let rotation = Self.screenRotation(of: screen)
		let image = try framebufferImage(screen: screen, orientation: rotation.framebufferImageOrientation)
		let target = rotation.displayedSize(native: device.nativePointSize)
		let scaled = Self.scaled(image, to: target) ?? image

		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
			throw SimulatorError.noFramebuffer
		}
		CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
		guard CGImageDestinationFinalize(destination) else {
			throw SimulatorError.noFramebuffer
		}
		return data as Data
	}

	/// A PNG of the screen at its native pixel size, turned the way the interface is — what
	/// Simulator.app's File ▸ Save Screen saves.
	public func screenshotPNG(udid: String) throws -> Data {
		let screen = try mainScreen(udid: udid)
		let image = try framebufferImage(screen: screen, orientation: Self.screenRotation(of: screen).framebufferImageOrientation)

		let data = NSMutableData()
		guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
			throw SimulatorError.noFramebuffer
		}
		CGImageDestinationAddImage(destination, image, nil)
		guard CGImageDestinationFinalize(destination) else {
			throw SimulatorError.noFramebuffer
		}
		return data as Data
	}

	private static func scaled(_ image: CGImage, to size: CGSize) -> CGImage? {
		let width = Int(size.width.rounded())
		let height = Int(size.height.rounded())
		guard
			width > 0,
			height > 0,
			let context = CGContext(
				data: nil,
				width: width,
				height: height,
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
			)
		else {
			return nil
		}
		context.interpolationQuality = .high
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		return context.makeImage()
	}

	// MARK: - Input

	func hidConnection(udid: String) async throws -> SimulatorHIDConnection {
		guard let version = Self.coreSimulatorVersion else {
			try Self.frameworkLoad.get()
			throw SimulatorError.frameworkUnavailable("unknown CoreSimulator version")
		}
		guard version.compare("1155.4", options: .numeric) != .orderedAscending else {
			throw SimulatorError.unsupportedCoreSimulator(version: version)
		}

		let device = try ObjectBox(object: simDevice(udid: udid))
		let task: Task<SimulatorHIDConnection, Error> = state.withLock { state in
			if let existing = state.hidConnections[udid], existing.isUsable {
				return Task { existing }
			}
			if let pending = state.pendingConnections[udid] {
				return pending
			}
			let task = Task { try await SimulatorHIDConnection.connect(to: device.object) }
			state.pendingConnections[udid] = task
			return task
		}

		do {
			let connection = try await task.value
			state.withLock {
				$0.hidConnections[udid] = connection
				$0.pendingConnections[udid] = nil
			}
			return connection
		}
		catch {
			state.withLock { $0.pendingConnections[udid] = nil }
			throw error
		}
	}

	/// Opens the input connection ahead of the first touch, so a click in a freshly shown pane
	/// does not wait out the daemon's start.
	public func prepareInput(udid: String) async {
		_ = try? await hidConnection(udid: udid)
	}

	/// One contact phase at a normalized point, for the pane's live mouse tracking.
	public func touch(udid: String, at point: CGPoint, phase: Int) async throws {
		guard let phase = SimulatorTouchPhase(rawValue: UInt64(phase)) else {
			return
		}
		try await hidConnection(udid: udid).touch(point, phase: phase)
	}

	public func tap(device: SimulatorDevice, x: Double, y: Double, holdFor duration: Duration = .milliseconds(60)) async throws {
		let point = try normalized(device: device, x: x, y: y)
		let connection = try await hidConnection(udid: device.id)
		connection.touch(point, phase: .began)
		try await Task.sleep(for: duration)
		connection.touch(point, phase: .ended)
		try await drain()
	}

	public func swipe(
		device: SimulatorDevice,
		from start: CGPoint,
		to end: CGPoint,
		duration: Duration = .milliseconds(300)
	) async throws {
		let from = try normalized(device: device, x: start.x, y: start.y)
		let to = try normalized(device: device, x: end.x, y: end.y)
		let connection = try await hidConnection(udid: device.id)

		let interval = Duration.milliseconds(16)
		let steps = max(2, Int(duration / interval))
		connection.touch(from, phase: .began)
		for step in 1...steps {
			try await Task.sleep(for: interval)
			let progress = CGFloat(step) / CGFloat(steps)
			connection.touch(
				CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress),
				phase: .moved
			)
		}
		connection.touch(to, phase: .ended)
		try await drain()
	}

	public func type(device: SimulatorDevice, text: String) async throws {
		let strokes = try SimulatorKeyboardMap.keyStrokes(for: text).get()
		let connection = try await hidConnection(udid: device.id)
		for stroke in strokes {
			try await press(stroke, on: connection)
		}
		try await drain()
	}

	/// Presses `keys` one after another, each released before the next, and drains once at the end.
	public func press(device: SimulatorDevice, keys: [SimulatorKeyStroke]) async throws {
		let connection = try await hidConnection(udid: device.id)
		for key in keys {
			try await press(key, on: connection)
		}
		try await drain()
	}

	/// A key from the pane's own keyboard handling: down and up, with modifiers, no drain wait.
	public func press(udid: String, key: SimulatorKeyStroke) async throws {
		try await press(key, on: hidConnection(udid: udid))
	}

	public func press(device: SimulatorDevice, button: SimulatorHardwareButton, holdFor duration: Duration = .milliseconds(100)) async throws {
		try await press(udid: device.id, button: button, holdFor: duration)
		try await drain()
	}

	public func press(udid: String, button: SimulatorHardwareButton, holdFor duration: Duration = .milliseconds(100)) async throws {
		let connection = try await hidConnection(udid: udid)
		connection.button(button, isDown: true)
		try await Task.sleep(for: duration)
		connection.button(button, isDown: false)
	}

	private func press(_ stroke: SimulatorKeyStroke, on connection: SimulatorHIDConnection) async throws {
		for modifier in stroke.modifiers {
			connection.key(usage: modifier, isDown: true)
		}
		connection.key(usage: stroke.usage, isDown: true)
		try await Task.sleep(for: .milliseconds(15))
		connection.key(usage: stroke.usage, isDown: false)
		for modifier in stroke.modifiers.reversed() {
			connection.key(usage: modifier, isDown: false)
		}
		try await Task.sleep(for: .milliseconds(15))
	}

	/// Sends are fire-and-forget; give the daemon time to deliver them before reporting done, so a
	/// screenshot taken right after a tap sees its effect begin.
	func drain() async throws {
		try await Task.sleep(for: .milliseconds(100))
	}

	func normalized(device: SimulatorDevice, x: Double, y: Double) throws -> CGPoint {
		guard let point = device.normalizedPoint(x: x, y: y) else {
			let size = device.screenPointSize
			throw SimulatorError.pointOutsideScreen(x: x, y: y, width: size.width, height: size.height)
		}
		return point
	}
}
