import Foundation

/// One arc of the sunburst: a node (or its parent's smallest children summed) at a depth, over
/// a span of the circle. Angles are fractions of a turn, 0 at the top, growing clockwise.
public struct SunburstSegment: Identifiable, Equatable, Sendable {
	public enum Content: Equatable, Sendable {
		case node(DiskNode)
		/// The parent's children too thin to draw on their own.
		case rest(count: Int, size: Int64)
	}

	/// What a segment stands for, the same in two layouts of related centres, so a transition
	/// between them can move it rather than redraw it (`SunburstTransition`).
	public enum Key: Hashable, Sendable {
		case node(ObjectIdentifier)
		/// A parent's summed smallest children, told by the parent.
		case rest(parent: ObjectIdentifier)
	}

	public let id: Int
	public let key: Key
	public let content: Content
	/// 1 for the centre node's children.
	public let depth: Int
	public let start: Double
	public let end: Double
	/// The nodes from the centre's child down to this segment's node, so the segment's
	/// location on disk can be told without parent pointers. Empty for a `rest` segment.
	public let ancestry: [DiskNode]

	public var span: Double { end - start }
	public var midpoint: Double { (start + end) / 2 }
	public var node: DiskNode? {
		if case let .node(node) = content { return node }
		return nil
	}
	public var size: Int64 {
		switch content {
		case let .node(node): node.size
		case let .rest(_, size): size
		}
	}
}

/// Lays the descendants of a centre node out in rings. A child takes the share of its parent's
/// span that its size is of the parent's; children thinner than `minimumSpan` are summed into
/// one `rest` segment at the end of the parent's span, and only children at least
/// `minimumSpanToDescend` wide are laid out further.
public struct SunburstLayout: Equatable, Sendable {
	public let center: DiskNode
	public let maxDepth: Int
	public let segments: [SunburstSegment]

	public init(center: DiskNode, maxDepth: Int = 6, minimumSpan: Double = 0.0015, minimumSpanToDescend: Double = 0.006) {
		self.center = center
		self.maxDepth = maxDepth
		var segments: [SunburstSegment] = []
		var nextID = 0
		func layOut(_ parent: DiskNode, ancestry: [DiskNode], depth: Int, start: Double, end: Double) {
			guard depth <= maxDepth, parent.size > 0 else { return }
			let scale = (end - start) / Double(parent.size)
			var cursor = start
			var restCount = 0
			var restSize: Int64 = 0
			for child in parent.children {
				let span = Double(child.size) * scale
				guard span >= minimumSpan else {
					restCount += 1
					restSize += child.size
					continue
				}
				let childAncestry = ancestry + [child]
				segments.append(SunburstSegment(id: nextID, key: .node(child.id), content: .node(child), depth: depth, start: cursor, end: cursor + span, ancestry: childAncestry))
				nextID += 1
				if child.isDirectory, span >= minimumSpanToDescend {
					layOut(child, ancestry: childAncestry, depth: depth + 1, start: cursor, end: cursor + span)
				}
				cursor += span
			}
			if restCount > 0 {
				let span = Double(restSize) * scale
				segments.append(SunburstSegment(id: nextID, key: .rest(parent: parent.id), content: .rest(count: restCount, size: restSize), depth: depth, start: cursor, end: cursor + span, ancestry: []))
				nextID += 1
			}
		}
		layOut(center, ancestry: [], depth: 1, start: 0, end: 1)
		self.segments = segments
	}

	/// The segment under a point given as a fraction of a turn and a ring depth.
	public func segment(atAngle angle: Double, depth: Int) -> SunburstSegment? {
		let angle = angle - angle.rounded(.down)
		return segments.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
	}

	/// The outermost ring's segment for a child of the centre, for the list beside the chart.
	public func segment(forChildNamed name: String) -> SunburstSegment? {
		segments.first { $0.depth == 1 && $0.node?.name == name }
	}

	/// The hue of a segment: where its middle lies on the circle, so neighbours shade into one
	/// another and a folder's children stay in its colour range.
	public static func hue(of segment: SunburstSegment) -> Double {
		segment.midpoint
	}
}
