import CoreGraphics
import Foundation

/// The `gesture` tool's presets: scrolls and edge swipes sized from the device's screen, so a model
/// need not work out coordinates for the common ones (AXe's `gesture`). Scrolls are named for what
/// they reveal, not for where the finger goes — `scroll_down` shows what is further down, the finger
/// moving up — because the finger's direction is the opposite and AXe's finger-named "scroll-up"
/// reads backwards.
nonisolated enum SimulatorGesturePreset: String, CaseIterable, Sendable {
	case scrollDown = "scroll_down"
	case scrollUp = "scroll_up"
	case scrollRight = "scroll_right"
	case scrollLeft = "scroll_left"
	case swipeFromLeftEdge = "swipe_from_left_edge"
	case swipeFromRightEdge = "swipe_from_right_edge"
	case swipeFromTopEdge = "swipe_from_top_edge"
	case swipeFromBottomEdge = "swipe_from_bottom_edge"

	/// Edge swipes start this far in: iOS's edge recognizers want a touch that begins at the edge.
	static let edgeInset: Double = 2

	struct Path: Equatable {
		var from: CGPoint
		var to: CGPoint
		var duration: Duration
	}

	/// The finger's path on a screen of `size` points. `position` moves it: for a scroll, the centre
	/// of the drag (inside a carousel or a side list); for an edge swipe, where along the edge it
	/// starts — x on the top and bottom edges, y on the sides. `distance` is how far a scroll
	/// drags, half the screen's height (or width) unless given.
	func path(in size: CGSize, position: CGPoint? = nil, distance: Double? = nil) -> Path {
		let centre = position ?? CGPoint(x: size.width / 2, y: size.height / 2)
		let w = size.width
		let h = size.height
		let inset = Self.edgeInset

		func scroll(dx: Double, dy: Double) -> Path {
			Path(
				from: CGPoint(x: clamp(centre.x - dx / 2, w), y: clamp(centre.y - dy / 2, h)),
				to: CGPoint(x: clamp(centre.x + dx / 2, w), y: clamp(centre.y + dy / 2, h)),
				duration: .milliseconds(500)
			)
		}
		let vertical = distance ?? h / 2
		let horizontal = distance ?? w / 2

		switch self {
		case .scrollDown:
			return scroll(dx: 0, dy: -vertical)
		case .scrollUp:
			return scroll(dx: 0, dy: vertical)
		case .scrollRight:
			return scroll(dx: -horizontal, dy: 0)
		case .scrollLeft:
			return scroll(dx: horizontal, dy: 0)
		case .swipeFromLeftEdge:
			return Path(from: CGPoint(x: inset, y: centre.y), to: CGPoint(x: w * 0.7, y: centre.y), duration: .milliseconds(300))
		case .swipeFromRightEdge:
			return Path(from: CGPoint(x: w - inset, y: centre.y), to: CGPoint(x: w * 0.3, y: centre.y), duration: .milliseconds(300))
		case .swipeFromTopEdge:
			return Path(from: CGPoint(x: centre.x, y: inset), to: CGPoint(x: centre.x, y: h * 0.6), duration: .milliseconds(300))
		case .swipeFromBottomEdge:
			return Path(from: CGPoint(x: centre.x, y: h - inset), to: CGPoint(x: centre.x, y: h * 0.4), duration: .milliseconds(250))
		}
	}

	private func clamp(_ value: Double, _ limit: Double) -> Double {
		min(max(value, 1), limit - 1)
	}

	static let toolDescription = """
	A common swipe sized from the screen, with no coordinates to work out. scroll_down shows what \
	is further down (the finger moves up), scroll_up what is above, scroll_right and scroll_left \
	what is to either side — half a screen by default. swipe_from_left_edge goes back in a \
	navigation stack; swipe_from_top_edge opens Notification Center from the top centre, or Control \
	Center with x near the right edge; swipe_from_bottom_edge goes home from an app (the home \
	indicator's swipe).
	"""
}
