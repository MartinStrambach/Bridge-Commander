import Foundation

/// How the sunburst gets from one centre to another, the way DaisyDisk zooms. Opening a folder,
/// its arc grows to the whole circle while sliding under the centre, its contents move one ring
/// inward and spread over the circle, and its siblings collapse into the seam at the top; going
/// up plays the same backwards. A change that is neither (a deletion, a rescan) keeps every
/// segment where it is and fades what changed, so the neighbours of a removed item sweep over it.
///
/// Every segment of either layout gets a frame in both: one it has in its own layout, and one
/// the zoom maps it to in the other. Interpolating between them with a progress from 0 to 1
/// moves the chart from the old picture to the new one; at 1 only the new layout is drawn.
public struct SunburstTransition: Equatable, Sendable {
	/// Where a segment is drawn at one moment. Angles are fractions of a turn; the depth is a
	/// fractional ring, 1 being the first ring, so below 1 lies under the centre and above the
	/// last ring lies outside the chart.
	public struct Frame: Equatable, Sendable {
		public var start: Double
		public var end: Double
		public var depth: Double
		public var opacity: Double

		public var span: Double { end - start }
		public var midpoint: Double { (start + end) / 2 }

		public init(start: Double, end: Double, depth: Double, opacity: Double = 1) {
			self.start = start
			self.end = end
			self.depth = depth
			self.opacity = opacity
		}

		init(_ segment: SunburstSegment) {
			self.init(start: segment.start, end: segment.end, depth: Double(segment.depth))
		}

		public func interpolated(to other: Frame, by progress: Double) -> Frame {
			Frame(
				start: start + (other.start - start) * progress,
				end: end + (other.end - end) * progress,
				depth: depth + (other.depth - depth) * progress,
				opacity: opacity + (other.opacity - opacity) * progress
			)
		}
	}

	/// A segment of either layout with its frame in both.
	public struct Member: Equatable, Sendable {
		public let segment: SunburstSegment
		public let from: Frame
		public let to: Frame
		/// A segment of the old layout only: it fades out and must not be highlighted, its `id`
		/// means nothing in the new layout.
		public let isLeaving: Bool
	}

	/// The arc of one layout that is the other layout's whole circle.
	public enum Zoom: Equatable, Sendable {
		/// The new centre was an arc of the old layout: the chart zooms into it.
		case into(start: Double, end: Double, depth: Int)
		/// The old centre is an arc of the new layout: the chart zooms out to it.
		case outOf(start: Double, end: Double, depth: Int)
		/// Neither: segments stay put and cross-fade.
		case none
	}

	public let from: SunburstLayout
	public let to: SunburstLayout
	public let zoom: Zoom
	/// Leaving segments first, so what stays paints over what goes.
	public let members: [Member]

	public init(from: SunburstLayout, to: SunburstLayout) {
		self.from = from
		self.to = to
		zoom = Self.zoom(from: from, to: to)
		var fromSegments: [SunburstSegment.Key: SunburstSegment] = [:]
		for segment in from.segments {
			fromSegments[segment.key] = segment
		}
		var members: [Member] = []
		var staying: [Member] = []
		for segment in to.segments {
			let toFrame = Frame(segment)
			if let old = fromSegments.removeValue(forKey: segment.key) {
				staying.append(Member(segment: segment, from: Frame(old), to: toFrame, isLeaving: false))
			}
			else {
				var fromFrame = zoom.oldFrame(of: toFrame)
				fromFrame.opacity = 0
				staying.append(Member(segment: segment, from: fromFrame, to: toFrame, isLeaving: false))
			}
		}
		for segment in from.segments where fromSegments[segment.key] != nil {
			let fromFrame = Frame(segment)
			var toFrame = zoom.newFrame(of: fromFrame)
			toFrame.opacity = 0
			members.append(Member(segment: segment, from: fromFrame, to: toFrame, isLeaving: true))
		}
		members.append(contentsOf: staying)
		self.members = members
	}

	/// Every segment's frame at a progress from 0 (the old layout) to 1 (the new one), skipping
	/// what would not be seen.
	public func frames(at progress: Double) -> [(segment: SunburstSegment, frame: Frame, isLeaving: Bool)] {
		members.compactMap { member in
			let frame = member.from.interpolated(to: member.to, by: progress)
			guard frame.span > 0, frame.opacity > 0 else { return nil }
			return (member.segment, frame, member.isLeaving)
		}
	}

	/// The new centre as an arc of the old layout, or the old centre as an arc of the new one. A
	/// centre too thin to have been drawn on its own is in its parent's `rest` arc, so that is
	/// what the chart zooms into or out of.
	private static func zoom(from: SunburstLayout, to: SunburstLayout) -> Zoom {
		if let arc = arc(of: to.center, in: from) {
			return .into(start: arc.start, end: arc.end, depth: arc.depth)
		}
		if let arc = arc(of: from.center, in: to) {
			return .outOf(start: arc.start, end: arc.end, depth: arc.depth)
		}
		return .none
	}

	private static func arc(of node: DiskNode, in layout: SunburstLayout) -> SunburstSegment? {
		if let segment = layout.segments.first(where: { $0.node === node }) {
			return segment
		}
		var ancestry: [DiskNode] = []
		guard Self.find(node, under: layout.center, ancestry: &ancestry) else { return nil }
		// The chain from the centre down to the node's parent; the deepest one drawn holds the rest.
		for depth in stride(from: ancestry.count, through: 1, by: -1) {
			let parent = ancestry[depth - 1]
			if let rest = layout.segments.first(where: { $0.key == .rest(parent: parent.id) }) {
				return rest
			}
		}
		return nil
	}

	/// Whether `node` is below `root`, leaving the chain `[root, …, parent]` in `ancestry`.
	private static func find(_ node: DiskNode, under root: DiskNode, ancestry: inout [DiskNode]) -> Bool {
		ancestry.append(root)
		for child in root.children {
			if child === node { return true }
			if child.isDirectory, Self.find(node, under: child, ancestry: &ancestry) { return true }
		}
		ancestry.removeLast()
		return false
	}
}

extension SunburstTransition.Zoom {
	/// Where a frame of the new layout was in the old one.
	func oldFrame(of frame: SunburstTransition.Frame) -> SunburstTransition.Frame {
		switch self {
		case let .into(start, end, depth):
			Self.widened(frame, to: start, end, depthShift: depth)
		case let .outOf(start, end, depth):
			Self.narrowed(frame, to: start, end, depthShift: -depth)
		case .none:
			frame
		}
	}

	/// Where a frame of the old layout goes in the new one.
	func newFrame(of frame: SunburstTransition.Frame) -> SunburstTransition.Frame {
		switch self {
		case let .into(start, end, depth):
			Self.narrowed(frame, to: start, end, depthShift: -depth)
		case let .outOf(start, end, depth):
			Self.widened(frame, to: start, end, depthShift: depth)
		case .none:
			frame
		}
	}

	/// The frame of a whole circle placed on the arc `start ... end`, `depthShift` rings further out.
	private static func widened(_ frame: SunburstTransition.Frame, to start: Double, _ end: Double, depthShift: Int) -> SunburstTransition.Frame {
		let span = end - start
		return SunburstTransition.Frame(
			start: start + frame.start * span,
			end: start + frame.end * span,
			depth: frame.depth + Double(depthShift),
			opacity: frame.opacity
		)
	}

	/// The frame of an arc when `start ... end` becomes the whole circle: what lies before the arc
	/// collapses onto the top of the circle, what lies after it onto the top from the other side.
	private static func narrowed(_ frame: SunburstTransition.Frame, to start: Double, _ end: Double, depthShift: Int) -> SunburstTransition.Frame {
		let span = end - start
		func map(_ angle: Double) -> Double {
			guard span > 0 else { return 0 }
			return min(1, max(0, (angle - start) / span))
		}
		return SunburstTransition.Frame(
			start: map(frame.start),
			end: map(frame.end),
			depth: frame.depth + Double(depthShift),
			opacity: frame.opacity
		)
	}
}
