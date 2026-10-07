import AppKit
import QuartzCore
import SwiftUI

/// Shows a booted simulator's screen live and turns clicks, drags, scrolls and typing into its
/// touches and keys.
///
/// The simulator renders into an `IOSurface` that this process can map, so the layer shows that
/// surface itself: no copy, no encode. CoreSimulator calls back once per presented frame
/// (`SimScreen`'s grouped callbacks, which idb also uses), and the layer is told its contents
/// changed; it calls back again when it replaces the surface (a rotation, a resolution change).
@MainActor
final class SimulatorScreenView: NSView {
	/// The device on screen; setting it reattaches.
	var deviceId: String? {
		didSet {
			guard deviceId != oldValue else {
				return
			}
			attach()
		}
	}

	/// The device's screen in pixels, for mapping a click to the image. The layer draws aspect-fit.
	var screenPixelSize: CGSize = .zero

	private let host = SimulatorHost.shared
	private var attachment: ScreenAttachment?
	private var surface: AnyObject?
	private var isRefreshScheduled = false
	/// Touches and keys run one after another, in the order the events came, on this chain.
	private var inputChain: Task<Void, Never>?
	private var isTouching = false
	private var scrollPoint: CGPoint?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.contentsGravity = .resizeAspect
		layer?.magnificationFilter = .linear
		layer?.minificationFilter = .trilinear
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var isFlipped: Bool {
		true
	}

	override var acceptsFirstResponder: Bool {
		true
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		true
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window == nil {
			detach()
		}
		else if attachment == nil {
			attach()
		}
	}

	// MARK: - Frames

	private func attach() {
		detach()
		guard let deviceId, window != nil else {
			return
		}

		let attachment = ScreenAttachment(deviceId: deviceId, host: host)
		self.attachment = attachment
		attachment.start(
			onSurface: { [weak self] surface in
				Task { @MainActor in
					guard let self, self.attachment === attachment else {
						return
					}
					self.surface = surface?.object
					self.layer?.contents = surface?.object
				}
			},
			onFrame: { [weak self] in
				Task { @MainActor in
					guard let self, self.attachment === attachment else {
						return
					}
					self.scheduleRefresh()
				}
			}
		)
	}

	private func detach() {
		attachment?.stop()
		attachment = nil
		surface = nil
		layer?.contents = nil
	}

	/// Coalesces a burst of frame callbacks into one layer update per main-loop turn.
	private func scheduleRefresh() {
		guard !isRefreshScheduled else {
			return
		}
		isRefreshScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else {
				return
			}
			self.isRefreshScheduled = false
			self.refreshContents()
		}
	}

	/// The surface is the same object frame after frame, so assigning it again changes nothing;
	/// `setContentsChanged` (what WebKit uses for the same situation) makes the layer re-read it.
	private func refreshContents() {
		guard let layer, let surface else {
			return
		}
		let selector = NSSelectorFromString("setContentsChanged")
		if layer.responds(to: selector) {
			layer.perform(selector)
		}
		else {
			layer.contents = nil
			layer.contents = surface
		}
	}

	// MARK: - Touches

	/// Where the screen is drawn in the view: aspect-fit, centred.
	private var imageRect: CGRect {
		guard screenPixelSize.width > 0, screenPixelSize.height > 0 else {
			return bounds
		}
		let scale = min(bounds.width / screenPixelSize.width, bounds.height / screenPixelSize.height)
		let size = CGSize(width: screenPixelSize.width * scale, height: screenPixelSize.height * scale)
		return CGRect(
			x: bounds.midX - size.width / 2,
			y: bounds.midY - size.height / 2,
			width: size.width,
			height: size.height
		)
	}

	private func normalized(_ point: CGPoint, clamped: Bool) -> CGPoint? {
		let rect = imageRect
		guard rect.width > 0, rect.height > 0 else {
			return nil
		}
		var x = (point.x - rect.minX) / rect.width
		var y = (point.y - rect.minY) / rect.height
		if clamped {
			x = min(max(x, 0), 1)
			y = min(max(y, 0), 1)
		}
		else if !(0...1).contains(x) || !(0...1).contains(y) {
			return nil
		}
		return CGPoint(x: x, y: y)
	}

	private func enqueue(_ work: @escaping @Sendable () async throws -> Void) {
		let previous = inputChain
		inputChain = Task {
			await previous?.value
			try? await work()
		}
	}

	private func touch(_ point: CGPoint, phase: Int) {
		guard let deviceId else {
			return
		}
		let host = host
		enqueue { try await host.touch(udid: deviceId, at: point, phase: phase) }
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		guard let point = normalized(convert(event.locationInWindow, from: nil), clamped: false) else {
			return
		}
		isTouching = true
		touch(point, phase: 0)
	}

	override func mouseDragged(with event: NSEvent) {
		guard isTouching, let point = normalized(convert(event.locationInWindow, from: nil), clamped: true) else {
			return
		}
		touch(point, phase: 1)
	}

	override func mouseUp(with event: NSEvent) {
		guard isTouching, let point = normalized(convert(event.locationInWindow, from: nil), clamped: true) else {
			return
		}
		isTouching = false
		touch(point, phase: 2)
	}

	/// A two-finger trackpad scroll drags a finger across the screen, so lists scroll the way they
	/// do under a finger. Momentum is left to the guest: the contact lifts when the fingers do.
	override func scrollWheel(with event: NSEvent) {
		guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
			return
		}

		let rect = imageRect
		switch event.phase {
		case .began:
			guard let start = normalized(convert(event.locationInWindow, from: nil), clamped: false) else {
				return
			}
			scrollPoint = start
			touch(start, phase: 0)
		case .changed:
			guard var point = scrollPoint, rect.width > 0, rect.height > 0 else {
				return
			}
			point.x = min(max(point.x + event.scrollingDeltaX / rect.width, 0), 1)
			point.y = min(max(point.y + event.scrollingDeltaY / rect.height, 0), 1)
			scrollPoint = point
			touch(point, phase: 1)
		case .ended, .cancelled:
			if let point = scrollPoint {
				touch(point, phase: 2)
			}
			scrollPoint = nil
		default:
			break
		}
	}

	// MARK: - Keys

	override func keyDown(with event: NSEvent) {
		guard let deviceId, let stroke = Self.keyStroke(for: event) else {
			super.keyDown(with: event)
			return
		}
		let host = host
		enqueue { try await host.press(udid: deviceId, key: stroke) }
	}

	/// The keystroke a Mac key event types on the simulated keyboard. ⌘ combinations are left to
	/// the app's own shortcuts.
	private static func keyStroke(for event: NSEvent) -> SimulatorKeyStroke? {
		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		guard !flags.contains(.command) else {
			return nil
		}

		let special: [UInt16: String] = [
			36: "return", 76: "return", 51: "delete", 117: "forwarddelete", 53: "escape", 48: "tab",
			123: "left", 124: "right", 125: "down", 126: "up",
		]
		var stroke: SimulatorKeyStroke?
		if let name = special[event.keyCode] {
			stroke = SimulatorKeyboardMap.keyStroke(named: name)
		}
		else if flags.contains(.control), let character = event.charactersIgnoringModifiers?.lowercased().first {
			stroke = SimulatorKeyboardMap.keyStroke(for: character)
			stroke?.modifiers.append(SimulatorKeyboardMap.leftControl)
		}
		else if let character = event.characters?.first {
			stroke = SimulatorKeyboardMap.keyStroke(for: character)
		}

		if flags.contains(.shift), var shifted = stroke, !shifted.modifiers.contains(SimulatorKeyboardMap.leftShift),
		   special[event.keyCode] != nil {
			shifted.modifiers.append(SimulatorKeyboardMap.leftShift)
			stroke = shifted
		}
		return stroke
	}
}

/// One registration of the screen callbacks, on its own serial queue as CoreSimulator requires: it
/// delivers each callback with `sync` onto that queue, so the callbacks stay tiny and hand off.
private final class ScreenAttachment: @unchecked Sendable {
	private let deviceId: String
	private let host: SimulatorHost
	private let token = UUID()
	private let queue = DispatchQueue(label: "com.bridgecommander.simulator.screen", qos: .userInteractive)
	private var screen: ObjectBox?
	private var isStopped = false

	init(deviceId: String, host: SimulatorHost) {
		self.deviceId = deviceId
		self.host = host
	}

	func start(onSurface: @escaping @Sendable (ObjectBox?) -> Void, onFrame: @escaping @Sendable () -> Void) {
		queue.async { [self] in
			guard !isStopped, let screen = try? host.mainScreen(udid: deviceId) else {
				return
			}
			self.screen = ObjectBox(object: screen)
			onSurface(Self.surface(of: screen, masked: nil, plain: nil))

			guard ObjCRuntime.responds(
				screen,
				to: "registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:"
			) else {
				return
			}
			ObjCRuntime.registerScreenCallbacks(
				on: screen,
				token: token,
				queue: queue,
				frame: { onFrame() },
				surfacesChanged: { plain, masked in
					onSurface(Self.surface(of: nil, masked: masked, plain: plain))
				},
				propertiesChanged: { _ in }
			)
		}
	}

	func stop() {
		queue.async { [self] in
			isStopped = true
			if let screen = screen?.object,
			   ObjCRuntime.responds(screen, to: "unregisterScreenCallbacksWithUUID:") {
				_ = ObjCRuntime.object(screen, "unregisterScreenCallbacksWithUUID:", token as NSUUID)
			}
			screen = nil
		}
	}

	/// The masked surface (the screen's own rounded corners and sensor housing cut out) when the
	/// display has one, else the full framebuffer.
	private static func surface(of screen: AnyObject?, masked: AnyObject?, plain: AnyObject?) -> ObjectBox? {
		if let screen {
			let masked = ObjCRuntime.responds(screen, to: "maskedFramebufferSurface")
				? ObjCRuntime.object(screen, "maskedFramebufferSurface")
				: nil
			return (masked ?? ObjCRuntime.object(screen, "framebufferSurface")).map(ObjectBox.init)
		}
		return (masked ?? plain).map(ObjectBox.init)
	}
}

/// `SimulatorScreenView` in SwiftUI.
struct SimulatorScreen: NSViewRepresentable {
	let deviceId: String
	let screenPixelSize: CGSize

	func makeNSView(context: Context) -> SimulatorScreenView {
		let view = SimulatorScreenView()
		view.screenPixelSize = screenPixelSize
		view.deviceId = deviceId
		return view
	}

	func updateNSView(_ view: SimulatorScreenView, context: Context) {
		view.screenPixelSize = screenPixelSize
		view.deviceId = deviceId
	}
}
