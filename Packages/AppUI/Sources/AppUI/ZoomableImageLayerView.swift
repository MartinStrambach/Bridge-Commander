import AppKit
import QuartzCore
import SwiftUI

/// Draws an image as a Core Animation layer's contents, applies `ImageZoom` as the layer's
/// transform, and handles the zoom gestures itself.
///
/// The gestures are plain AppKit event handling (`magnify`, `mouseDown`, `mouseDragged`), not
/// SwiftUI gestures. With a SwiftUI double-tap beside a drag, AppKit held the drag's events back
/// while it waited for a second click and delivered them in bursts of ~25 every ~0.6 s, so panning
/// jumped instead of following the pointer. Drawing through the layer means a zoom or pan costs a
/// GPU composite and never a redraw.
struct ZoomableImageLayerView: NSViewRepresentable {
	let image: CGImage
	@Binding var zoom: ImageZoom

	func makeNSView(context: Context) -> ZoomableImageNSView {
		ZoomableImageNSView()
	}

	func updateNSView(_ nsView: ZoomableImageNSView, context: Context) {
		nsView.onZoomChange = { zoom = $0 }
		nsView.onReset = { withAnimation(.snappy) { zoom = .identity } }
		// A SwiftUI animation (the reset) becomes a Core Animation one; gesture updates carry none
		// and apply immediately.
		nsView.update(image: image, zoom: zoom, animated: context.transaction.animation != nil)
	}
}

final class ZoomableImageNSView: NSView {
	var onZoomChange: (ImageZoom) -> Void = { _ in }
	var onReset: () -> Void = {}

	private let imageLayer = CALayer()
	private var zoom = ImageZoom.identity

	/// The zoom a gesture in progress started from; both gestures are applied relative to it.
	private var gestureBase: ImageZoom?
	private var dragStart: NSPoint?
	/// Product of a pinch's per-event magnification deltas, i.e. its total factor so far.
	private var pinchFactor: CGFloat = 1
	/// Where the pinch began, as `ImageZoom.magnified(by:anchor:)` expects: fixed for the gesture.
	private var pinchAnchor = UnitPoint.center

	init() {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.masksToBounds = true
		imageLayer.contentsGravity = .resize
		layer?.addSublayer(imageLayer)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layout() {
		super.layout()
		applyGeometry(animated: false)
	}

	func update(image: CGImage, zoom: ImageZoom, animated: Bool) {
		if (imageLayer.contents as AnyObject?) !== image {
			CATransaction.begin()
			CATransaction.setDisableActions(true)
			imageLayer.contents = image
			CATransaction.commit()
		}

		if zoom.isZoomed != self.zoom.isZoomed {
			window?.invalidateCursorRects(for: self)
		}

		self.zoom = zoom
		applyGeometry(animated: animated)
	}

	// MARK: - Events

	override func magnify(with event: NSEvent) {
		switch event.phase {
		case .began:
			guard bounds.width > 0, bounds.height > 0 else {
				return
			}

			gestureBase = zoom
			pinchFactor = 1
			let location = convert(event.locationInWindow, from: nil)
			// The view is not flipped; `UnitPoint` y grows downward.
			pinchAnchor = UnitPoint(x: location.x / bounds.width, y: 1 - location.y / bounds.height)

		case .ended, .cancelled:
			gestureBase = nil
			return

		default:
			break
		}

		guard let base = gestureBase else {
			return
		}

		pinchFactor *= 1 + event.magnification
		onZoomChange(base.magnified(by: pinchFactor, anchor: pinchAnchor))
	}

	override func mouseDown(with event: NSEvent) {
		if event.clickCount == 2 {
			onReset()
			return
		}

		guard zoom.isZoomed else {
			return
		}

		gestureBase = zoom
		dragStart = convert(event.locationInWindow, from: nil)
		NSCursor.closedHand.push()
	}

	override func mouseDragged(with event: NSEvent) {
		guard let base = gestureBase, let dragStart else {
			return
		}

		let location = convert(event.locationInWindow, from: nil)
		// `ImageZoom` follows SwiftUI, where y grows downward.
		let translation = CGSize(width: location.x - dragStart.x, height: dragStart.y - location.y)
		onZoomChange(base.panned(by: translation, fittedSize: bounds.size))
	}

	override func mouseUp(with event: NSEvent) {
		guard dragStart != nil else {
			return
		}

		gestureBase = nil
		dragStart = nil
		NSCursor.pop()
	}

	override func resetCursorRects() {
		if zoom.isZoomed {
			addCursorRect(bounds, cursor: .openHand)
		}
	}

	// MARK: - Geometry

	private func applyGeometry(animated: Bool) {
		CATransaction.begin()
		if animated {
			CATransaction.setAnimationDuration(0.25)
		}
		else {
			CATransaction.setDisableActions(true)
		}

		let size = bounds.size
		imageLayer.bounds = CGRect(origin: .zero, size: size)
		// The view is not flipped, so layer y grows upward while `ImageZoom`'s offset grows downward.
		imageLayer.position = CGPoint(
			x: size.width / 2 + zoom.offset.width * size.width,
			y: size.height / 2 - zoom.offset.height * size.height
		)
		imageLayer.setAffineTransform(CGAffineTransform(scaleX: zoom.scale, y: zoom.scale))
		CATransaction.commit()
	}
}
