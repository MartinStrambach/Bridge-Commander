import CoreGraphics
import SwiftUI

/// Zoom and pan of an image drawn aspect-fit in a frame, shared by the panes of an image diff so
/// Before and After stay aligned.
///
/// The offset is a fraction of the image's fitted (unzoomed) size rather than points, because the
/// two panes can draw their images at different sizes: the same fraction lands on the same spot of
/// each image. `scale` 1 with a zero offset is the unzoomed image.
public struct ImageZoom: Equatable, Sendable {
	public static let minScale: CGFloat = 1
	public static let maxScale: CGFloat = 16
	public static let identity = ImageZoom()

	public private(set) var scale: CGFloat = 1
	/// Shift of the image's center from the frame's center, in units of the fitted image size.
	public private(set) var offset: CGSize = .zero

	public init() {}

	public init(scale: CGFloat, offset: CGSize) {
		self.scale = min(max(scale, Self.minScale), Self.maxScale)
		self.offset = Self.clamped(offset, scale: self.scale)
	}

	public var isZoomed: Bool {
		scale > Self.minScale
	}

	/// Zooms by `factor` relative to this state, keeping the image point under `anchor` (a unit
	/// point in the fitted image, as `MagnifyGesture` reports it) where it is on screen.
	public func magnified(by factor: CGFloat, anchor: UnitPoint) -> ImageZoom {
		let newScale = min(max(scale * factor, Self.minScale), Self.maxScale)
		// Center-relative position of the anchor on screen, and the image point currently under it.
		let anchorX = anchor.x - 0.5
		let anchorY = anchor.y - 0.5
		let pointX = (anchorX - offset.width) / scale
		let pointY = (anchorY - offset.height) / scale
		return ImageZoom(
			scale: newScale,
			offset: CGSize(width: anchorX - pointX * newScale, height: anchorY - pointY * newScale)
		)
	}

	/// Pans by `translation` points, given the image's fitted size in points.
	public func panned(by translation: CGSize, fittedSize: CGSize) -> ImageZoom {
		guard fittedSize.width > 0, fittedSize.height > 0 else {
			return self
		}

		return ImageZoom(
			scale: scale,
			offset: CGSize(
				width: offset.width + translation.width / fittedSize.width,
				height: offset.height + translation.height / fittedSize.height
			)
		)
	}

	/// Keeps the zoomed image covering the frame, so panning can never reveal empty space beside it.
	private static func clamped(_ offset: CGSize, scale: CGFloat) -> CGSize {
		let limit = (scale - 1) / 2
		return CGSize(
			width: min(max(offset.width, -limit), limit),
			height: min(max(offset.height, -limit), limit)
		)
	}
}
