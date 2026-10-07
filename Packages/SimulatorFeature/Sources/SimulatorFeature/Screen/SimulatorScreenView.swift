import AppKit
import QuartzCore
import SwiftUI

/// Shows a booted simulator's screen live and turns clicks, drags, scrolls and typing into its
/// touches and keys.
///
/// The simulator renders into an `IOSurface` that this process can map, so the layer shows that
/// surface itself: no copy, no encode. CoreSimulator calls back once per presented frame
/// (`SimScreen`'s grouped callbacks, which idb also uses), and the layer is told its contents
/// changed; it calls back again when it replaces the surface (a resolution change).
///
/// The framebuffer stays portrait when the interface rotates — a landscape app is drawn sideways
/// into it — so the surface sits in a sublayer turned to bring the interface upright, and the
/// view's own coordinates (clicks, finger indicators) are the interface's. They are turned back to
/// the portrait panel's only as touches are sent, since that is the space the digitizer takes.
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

	/// The device's screen in pixels, portrait, for mapping a click to the image. The layer draws
	/// aspect-fit.
	var screenPixelSize: CGSize = .zero {
		didSet {
			if screenPixelSize != oldValue {
				layoutScreenLayer()
			}
		}
	}

	/// How the interface is turned, as the screen's properties report it — straight from
	/// CoreSimulator rather than the pane's device poll, so the picture turns with the device.
	private(set) var rotation: SimulatorScreenRotation = .upright {
		didSet {
			if rotation != oldValue {
				layoutScreenLayer()
			}
		}
	}

	/// Holds the framebuffer surface, turned upright.
	private let screenLayer: CALayer = {
		let layer = CALayer()
		layer.contentsGravity = .resize
		layer.magnificationFilter = .linear
		layer.minificationFilter = .trilinear
		return layer
	}()

	private let host = SimulatorHost.shared
	private var attachment: ScreenAttachment?
	private var surface: AnyObject?
	private var isRefreshScheduled = false
	/// Touches and keys run one after another, in the order the events came, on this chain.
	private var inputChain: Task<Void, Never>?
	private var scrollPoint: CGPoint?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.addSublayer(screenLayer)
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

	override func layout() {
		super.layout()
		layoutScreenLayer()
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		layoutScreenLayer()
	}

	/// Sizes the surface's layer to the portrait panel at the scale the interface is shown at, and
	/// turns it about the centre of the shown image. The view is flipped (y down), so a positive
	/// angle turns clockwise.
	private func layoutScreenLayer() {
		let rect = imageRect
		let nativeSize = rotation.isLandscape ? CGSize(width: rect.height, height: rect.width) : rect.size
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		screenLayer.setAffineTransform(.identity)
		screenLayer.bounds = CGRect(origin: .zero, size: nativeSize)
		screenLayer.position = CGPoint(x: rect.midX, y: rect.midY)
		screenLayer.setAffineTransform(CGAffineTransform(rotationAngle: rotation.uprightingAngle))
		CATransaction.commit()
	}

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
					self.screenLayer.contents = surface?.object
				}
			},
			onRotation: { [weak self] rotation in
				Task { @MainActor in
					guard let self, self.attachment === attachment else {
						return
					}
					self.rotation = rotation
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
		screenLayer.contents = nil
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
		guard let surface else {
			return
		}
		let layer = screenLayer
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

	/// Where the screen is drawn in the view, the way the interface is turned: aspect-fit, centred.
	private var imageRect: CGRect {
		let displayedSize = rotation.displayedSize(native: screenPixelSize)
		guard displayedSize.width > 0, displayedSize.height > 0 else {
			return bounds
		}
		let scale = min(bounds.width / displayedSize.width, bounds.height / displayedSize.height)
		let size = CGSize(width: displayedSize.width * scale, height: displayedSize.height * scale)
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

	/// A normalized point in the view's (interface) space on the portrait panel the digitizer maps.
	private func panelPoint(_ point: CGPoint) -> CGPoint {
		rotation.nativePoint(fromDisplayed: point, nativeSize: CGSize(width: 1, height: 1))
	}

	private func touch(_ point: CGPoint, phase: Int) {
		guard let deviceId else {
			return
		}
		let host = host
		let panelPoint = panelPoint(point)
		enqueue { try await host.touch(udid: deviceId, at: panelPoint, phase: phase) }
	}

	private func touch(_ fingers: FingerPair, phase: Int) {
		guard let deviceId else {
			return
		}
		let host = host
		let panelFingers = FingerPair(panelPoint(fingers.first), panelPoint(fingers.second))
		enqueue { try await host.twoFingerTouch(udid: deviceId, fingers: panelFingers, phase: phase) }
		showIndicators(phase == 2 ? nil : fingers)
	}

	// MARK: - Mouse

	/// What a mouse press is driving: one finger, or two the way Simulator.app does it — with ⌥ the
	/// second finger mirrors the pointer across the screen's centre (pinch, rotate), with ⌥⇧ it
	/// keeps its offset and both move together (two-finger drag).
	private enum MouseContact {
		case oneFinger
		case mirrored
		case parallel(offset: CGPoint)
	}

	private var mouseContact: MouseContact?

	private static func mirrored(_ point: CGPoint) -> CGPoint {
		CGPoint(x: 1 - point.x, y: 1 - point.y)
	}

	private func fingers(for point: CGPoint, contact: MouseContact) -> FingerPair? {
		switch contact {
		case .oneFinger:
			nil
		case .mirrored:
			FingerPair(point, Self.mirrored(point))
		case let .parallel(offset):
			FingerPair(point, CGPoint(x: min(max(point.x + offset.x, 0), 1), y: min(max(point.y + offset.y, 0), 1)))
		}
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		guard let point = normalized(convert(event.locationInWindow, from: nil), clamped: false) else {
			return
		}

		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		let contact: MouseContact = if !flags.contains(.option) {
			.oneFinger
		}
		else if flags.contains(.shift) {
			.parallel(offset: CGPoint(x: Self.mirrored(point).x - point.x, y: Self.mirrored(point).y - point.y))
		}
		else {
			.mirrored
		}
		mouseContact = contact
		if let fingers = fingers(for: point, contact: contact) {
			touch(fingers, phase: 0)
		}
		else {
			touch(point, phase: 0)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		guard let contact = mouseContact, let point = normalized(convert(event.locationInWindow, from: nil), clamped: true) else {
			return
		}
		if let fingers = fingers(for: point, contact: contact) {
			touch(fingers, phase: 1)
		}
		else {
			touch(point, phase: 1)
		}
	}

	override func mouseUp(with event: NSEvent) {
		guard let contact = mouseContact, let point = normalized(convert(event.locationInWindow, from: nil), clamped: true) else {
			return
		}
		mouseContact = nil
		if let fingers = fingers(for: point, contact: contact) {
			touch(fingers, phase: 2)
		}
		else {
			touch(point, phase: 2)
		}
		updateHoverIndicators(modifierFlags: event.modifierFlags)
	}

	// MARK: - Trackpad pinch and rotate

	/// A trackpad pinch or rotation becomes the same two-finger gesture on the device, centred on
	/// the pointer. Both can run at once (pinch while turning), so they share one contact that
	/// lifts when the last of them ends.
	private struct TrackpadGesture {
		var center: CGPoint
		var scale: CGFloat = 1
		var rotationDegrees: CGFloat = 0
		var active: Set<String> = []
	}

	private var trackpadGesture: TrackpadGesture?
	/// Half the fingers' spacing at the start of a trackpad gesture, in view points.
	private static let trackpadFingerRadius: CGFloat = 40

	private func trackpadFingers(_ gesture: TrackpadGesture) -> FingerPair? {
		let rect = imageRect
		guard rect.width > 0, rect.height > 0 else {
			return nil
		}
		// The view is flipped, so the trackpad's counter-clockwise turn is a negative angle here.
		let angle = -gesture.rotationDegrees * .pi / 180
		let radius = Self.trackpadFingerRadius * max(gesture.scale, 0.1)
		let dx = radius * cos(angle) / rect.width
		let dy = radius * sin(angle) / rect.height
		func clamp(_ point: CGPoint) -> CGPoint {
			CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
		}
		return FingerPair(
			clamp(CGPoint(x: gesture.center.x - dx, y: gesture.center.y - dy)),
			clamp(CGPoint(x: gesture.center.x + dx, y: gesture.center.y + dy))
		)
	}

	private func trackpadGesture(_ name: String, event: NSEvent, update: (inout TrackpadGesture) -> Void) {
		switch event.phase {
		case .began:
			if trackpadGesture == nil {
				guard let center = normalized(convert(event.locationInWindow, from: nil), clamped: false) else {
					return
				}
				let gesture = TrackpadGesture(center: center)
				trackpadGesture = gesture
				if let fingers = trackpadFingers(gesture) {
					touch(fingers, phase: 0)
				}
			}
			trackpadGesture?.active.insert(name)
		case .changed:
			guard var gesture = trackpadGesture else {
				return
			}
			update(&gesture)
			trackpadGesture = gesture
			if let fingers = trackpadFingers(gesture) {
				touch(fingers, phase: 1)
			}
		case .ended, .cancelled:
			guard var gesture = trackpadGesture else {
				return
			}
			gesture.active.remove(name)
			if gesture.active.isEmpty {
				trackpadGesture = nil
				if let fingers = trackpadFingers(gesture) {
					touch(fingers, phase: 2)
				}
			}
			else {
				trackpadGesture = gesture
			}
		default:
			break
		}
	}

	override func magnify(with event: NSEvent) {
		trackpadGesture("magnify", event: event) { $0.scale = max($0.scale * (1 + event.magnification), 0.1) }
	}

	override func rotate(with event: NSEvent) {
		trackpadGesture("rotate", event: event) { $0.rotationDegrees += CGFloat(event.rotation) }
	}

	// MARK: - Finger indicators

	/// Two dots where the fingers are — while ⌥ is held over the screen, before and during a
	/// two-finger gesture — as Simulator.app draws them.
	private lazy var indicatorLayers: [CAShapeLayer] = (0..<2).map { _ in
		let layer = CAShapeLayer()
		let diameter: CGFloat = 22
		layer.path = CGPath(ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter), transform: nil)
		layer.fillColor = NSColor.white.withAlphaComponent(0.45).cgColor
		layer.strokeColor = NSColor.black.withAlphaComponent(0.35).cgColor
		layer.lineWidth = 1
		layer.isHidden = true
		layer.zPosition = 1
		self.layer?.addSublayer(layer)
		return layer
	}

	private func showIndicators(_ fingers: FingerPair?) {
		let rect = imageRect
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		for (layer, point) in zip(indicatorLayers, [fingers?.first, fingers?.second]) {
			if let point {
				layer.position = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
				layer.isHidden = false
			}
			else {
				layer.isHidden = true
			}
		}
		CATransaction.commit()
	}

	private func updateHoverIndicators(modifierFlags: NSEvent.ModifierFlags) {
		guard mouseContact == nil, trackpadGesture == nil else {
			return
		}
		guard
			modifierFlags.contains(.option),
			let window,
			let point = normalized(convert(window.mouseLocationOutsideOfEventStream, from: nil), clamped: false)
		else {
			showIndicators(nil)
			return
		}
		showIndicators(FingerPair(point, Self.mirrored(point)))
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		for area in trackingAreas {
			removeTrackingArea(area)
		}
		addTrackingArea(NSTrackingArea(
			rect: .zero,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseMoved(with event: NSEvent) {
		updateHoverIndicators(modifierFlags: event.modifierFlags)
	}

	override func mouseExited(with event: NSEvent) {
		if mouseContact == nil, trackpadGesture == nil {
			showIndicators(nil)
		}
	}

	override func flagsChanged(with event: NSEvent) {
		super.flagsChanged(with: event)
		updateHoverIndicators(modifierFlags: event.modifierFlags)
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

	func start(
		onSurface: @escaping @Sendable (ObjectBox?) -> Void,
		onRotation: @escaping @Sendable (SimulatorScreenRotation) -> Void,
		onFrame: @escaping @Sendable () -> Void
	) {
		queue.async { [self] in
			guard !isStopped, let screen = try? host.mainScreen(udid: deviceId) else {
				return
			}
			self.screen = ObjectBox(object: screen)
			onSurface(Self.surface(of: screen, masked: nil, plain: nil))
			onRotation(SimulatorHost.screenRotation(of: screen))

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
				// Delivers the screen's new properties — among them `uiOrientation` when the
				// interface turns.
				propertiesChanged: { properties in
					onRotation(properties.map(SimulatorHost.screenRotation(ofProperties:)) ?? SimulatorHost.screenRotation(of: screen))
				}
			)
		}
	}

	func stop() {
		queue.async { [self] in
			isStopped = true
			if let screen = screen?.object,
			   ObjCRuntime.responds(screen, to: "unregisterScreenCallbacksWithUUID:") {
				ObjCRuntime.send(screen, "unregisterScreenCallbacksWithUUID:", token as NSUUID)
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
