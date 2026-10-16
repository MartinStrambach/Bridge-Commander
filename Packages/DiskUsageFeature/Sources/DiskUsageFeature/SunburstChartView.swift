import AppKit
import AppUI
import SwiftUI

/// The sunburst: the folder on screen at the centre, its contents in rings around it, largest
/// first clockwise from the top. Hovering names a segment, clicking a folder opens it, clicking
/// the centre goes up. A change of centre is animated as a zoom (`SunburstTransition`).
struct SunburstChartView: View {
	let layout: SunburstLayout
	/// Whether clicking the centre can go up.
	let canGoUp: Bool
	@Binding
	var hovered: SunburstSegment?
	let selectedNames: Set<String>
	let onOpen: (DiskNode) -> Void
	let onGoUp: () -> Void
	/// A plain click: the first-ring item alone, or nothing.
	let onSelect: (DiskNode?) -> Void
	/// ⌘-click: the first-ring item into or out of the selection.
	let onToggle: (DiskNode) -> Void

	/// The zoom under way, if any, and the `phase` value it ends at. The phase only ever grows:
	/// an animatable value is interpolated from what was last drawn, so a transition that reset
	/// it to 0 and animated it to 1 in one update would not move at all.
	@State
	private var transition: (transition: SunburstTransition, end: Int)?
	@State
	private var phase: Double = 0

	@Environment(\.colorScheme)
	private var colorScheme
	@Environment(\.accessibilityReduceMotion)
	private var reduceMotion

	private static let zoomDuration: TimeInterval = 0.5

	var body: some View {
		GeometryReader { geometry in
			let geometry = ChartGeometry(size: geometry.size, maxDepth: layout.maxDepth)
			ZStack {
				SunburstCanvas(
					layout: layout,
					transition: transition?.transition,
					transitionEnd: transition?.end ?? 0,
					phase: phase,
					hovered: hovered,
					selectedNames: selectedNames,
					canGoUp: canGoUp,
					colorScheme: colorScheme,
					geometry: geometry
				)
				centerLabel(geometry: geometry)
			}
			.contentShape(Rectangle())
			.onContinuousHover { phase in
				switch phase {
				case let .active(location):
					hovered = segment(at: location, geometry: geometry)
				case .ended:
					hovered = nil
				}
			}
			.onTapGesture { location in
				tapped(at: location, geometry: geometry)
			}
			.overlay(alignment: .topLeading) {
				if let hovered {
					tooltip(for: hovered)
				}
			}
		}
		.aspectRatio(1, contentMode: .fit)
		.onChange(of: layout) { old, new in
			zoom(from: old, to: new)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Disk usage of \(layout.center.name): \(layout.center.size.formatted(.byteCount(style: .file)))")
	}

	// MARK: - Animation

	private func zoom(from old: SunburstLayout, to new: SunburstLayout) {
		guard !reduceMotion else {
			transition = nil
			return
		}
		// A zoom started while one is under way takes off from where that one was going.
		let end = (transition?.end ?? Int(phase.rounded(.up))) + 1
		transition = (SunburstTransition(from: old, to: new), end)
		withAnimation(.easeInOut(duration: Self.zoomDuration)) {
			phase = Double(end)
		} completion: {
			if transition?.end == end {
				transition = nil
			}
		}
	}

	// MARK: - Labels

	private func centerLabel(geometry: ChartGeometry) -> some View {
		VStack(spacing: 2) {
			if canGoUp {
				Image(systemName: "arrow.up")
					.scaledFont(.caption2)
					.foregroundStyle(.secondary)
			}
			Text(layout.center.name == "/" ? "/" : URL(filePath: layout.center.name).lastPathComponent)
				.scaledFont(.callout)
				.fontWeight(.semibold)
				.lineLimit(2)
				.multilineTextAlignment(.center)
			Text(layout.center.size.formatted(.byteCount(style: .file)))
				.scaledFont(.caption)
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.frame(width: geometry.innerRadius * 1.6)
		// A new centre's label fades in over the old one's while the rings zoom.
		.id(layout.center.id)
		.transition(.opacity)
		.animation(reduceMotion ? nil : .easeInOut(duration: Self.zoomDuration * 0.6), value: layout.center.id)
		.position(geometry.center)
		.allowsHitTesting(false)
	}

	private func tooltip(for segment: SunburstSegment) -> some View {
		let share = layout.center.size > 0 ? Double(segment.size) / Double(layout.center.size) : 0
		return VStack(alignment: .leading, spacing: 2) {
			switch segment.content {
			case let .node(node):
				Text(node.name)
					.fontWeight(.semibold)
					.lineLimit(1)
				if node.isInaccessible {
					Text("Could not be read")
						.foregroundStyle(.secondary)
				}
				else if node.isDirectory {
					Text("\(node.itemCount.formatted()) items")
						.foregroundStyle(.secondary)
				}
			case let .rest(count, _):
				Text("\(count.formatted()) smaller items")
					.fontWeight(.semibold)
			}
			Text("\(segment.size.formatted(.byteCount(style: .file))) · \(share.formatted(.percent.precision(.fractionLength(1))))")
				.monospacedDigit()
				.foregroundStyle(.secondary)
		}
		.scaledFont(.caption)
		.padding(8)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
		.padding(8)
		.allowsHitTesting(false)
	}

	// MARK: - Hit testing

	private func segment(at location: CGPoint, geometry: ChartGeometry) -> SunburstSegment? {
		let dx = location.x - geometry.center.x
		let dy = location.y - geometry.center.y
		let distance = (dx * dx + dy * dy).squareRoot()
		guard distance >= geometry.innerRadius else { return nil }
		let depth = Int((distance - geometry.innerRadius) / geometry.ringWidth) + 1
		guard depth <= layout.maxDepth else { return nil }
		// atan2 of (x, -y) measures clockwise from the top.
		var angle = atan2(dx, -dy) / (2 * .pi)
		if angle < 0 { angle += 1 }
		return layout.segment(atAngle: angle, depth: depth)
	}

	private func tapped(at location: CGPoint, geometry: ChartGeometry) {
		let dx = location.x - geometry.center.x
		let dy = location.y - geometry.center.y
		if (dx * dx + dy * dy).squareRoot() < geometry.innerRadius {
			if canGoUp { onGoUp() }
			return
		}
		guard let segment = segment(at: location, geometry: geometry), let node = segment.node else {
			onSelect(nil)
			return
		}
		if NSEvent.modifierFlags.contains(.command), let topLevel = segment.ancestry.first {
			onToggle(topLevel)
		}
		else if node.isDirectory, !node.isInaccessible, segment.depth == 1 {
			onOpen(node)
		}
		else if let topLevel = segment.ancestry.first {
			onSelect(topLevel)
		}
	}
}

/// The rings, drawn in a `Canvas`. Animatable by `phase`: while a transition is under way, the
/// segments are drawn where the transition puts them at the phase's progress towards
/// `transitionEnd`; otherwise the layout is drawn as it is.
private struct SunburstCanvas: View, Animatable {
	let layout: SunburstLayout
	let transition: SunburstTransition?
	let transitionEnd: Int
	var phase: Double
	let hovered: SunburstSegment?
	let selectedNames: Set<String>
	let canGoUp: Bool
	let colorScheme: ColorScheme
	let geometry: ChartGeometry

	nonisolated var animatableData: Double {
		get { phase }
		set { phase = newValue }
	}

	var body: some View {
		Canvas { context, _ in
			draw(in: &context)
		}
	}

	private func draw(in context: inout GraphicsContext) {
		// The ring band: an arc on its way under the centre or in from outside is cut at its edge.
		var band = Path(ellipseIn: CGRect(
			x: geometry.center.x - geometry.outerRadius,
			y: geometry.center.y - geometry.outerRadius,
			width: geometry.outerRadius * 2,
			height: geometry.outerRadius * 2
		))
		band.addPath(Self.circle(around: geometry.center, radius: geometry.innerRadius))
		var rings = context
		rings.clip(to: band, style: FillStyle(eoFill: true))
		if let transition {
			let progress = min(1, max(0, phase - Double(transitionEnd - 1)))
			for (segment, frame, isLeaving) in transition.frames(at: progress) {
				draw(segment, at: frame, highlightable: !isLeaving, in: &rings)
			}
		}
		else {
			for segment in layout.segments {
				draw(segment, at: SunburstTransition.Frame(segment), highlightable: true, in: &rings)
			}
		}
		context.fill(Self.circle(around: geometry.center, radius: geometry.innerRadius), with: .color(Color.primary.opacity(canGoUp ? 0.07 : 0.04)))
	}

	private func draw(_ segment: SunburstSegment, at frame: SunburstTransition.Frame, highlightable: Bool, in context: inout GraphicsContext) {
		guard let path = arcPath(for: frame) else { return }
		let isHovered = highlightable && hovered?.id == segment.id
		let isSelected = highlightable && segment.ancestry.first.map { selectedNames.contains($0.name) } == true
		var color = color(of: segment, at: frame)
		if let hovered, !isHovered, !isRelated(segment, to: hovered) {
			color = color.opacity(0.45)
		}
		context.opacity = frame.opacity
		context.fill(path, with: .color(color))
		if isHovered || isSelected {
			context.stroke(path, with: .color(.primary.opacity(isHovered ? 0.9 : 0.6)), lineWidth: isHovered ? 2 : 1.5)
		}
		else {
			context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
		}
	}

	/// Segments on the same branch as the hovered one keep their full colour.
	private func isRelated(_ segment: SunburstSegment, to hovered: SunburstSegment) -> Bool {
		guard let hoveredNode = hovered.node else { return false }
		return segment.ancestry.contains(where: { $0 === hoveredNode }) || hovered.ancestry.contains(where: { $0 === segment.node })
	}

	/// The arc of a frame, or nil when it lies wholly under the centre or outside the chart.
	private func arcPath(for frame: SunburstTransition.Frame) -> Path? {
		let inner = geometry.innerRadius + CGFloat(frame.depth - 1) * geometry.ringWidth
		let outer = inner + geometry.ringWidth - 0.5
		guard outer > geometry.innerRadius, inner < geometry.outerRadius else { return nil }
		// Radians from the top, clockwise; SwiftUI's angles grow clockwise from the right.
		let startAngle = Angle(radians: frame.start * 2 * .pi - .pi / 2)
		let endAngle = Angle(radians: frame.end * 2 * .pi - .pi / 2)
		var path = Path()
		path.addArc(center: geometry.center, radius: outer, startAngle: startAngle, endAngle: endAngle, clockwise: false)
		path.addArc(center: geometry.center, radius: inner, startAngle: endAngle, endAngle: startAngle, clockwise: true)
		path.closeSubpath()
		return path
	}

	/// The hue is the frame's midpoint, so a segment's colour slides with it along the circle as
	/// it zooms and lands on the colour it has in the new layout.
	private func color(of segment: SunburstSegment, at frame: SunburstTransition.Frame) -> Color {
		switch segment.content {
		case .rest:
			return Color.gray.opacity(0.35)
		case let .node(node):
			if node.isInaccessible || node.isHiddenSpace {
				return Color.gray.opacity(0.5)
			}
			let depthFade = max(0, frame.depth - 1) * 0.06
			let isFile = !node.isDirectory
			return Color(
				hue: min(1, max(0, frame.midpoint)),
				saturation: max(0.25, (isFile ? 0.4 : 0.62) - depthFade),
				brightness: colorScheme == .dark ? min(1, 0.8 + depthFade) : max(0.6, 0.92 - depthFade)
			)
		}
	}

	private static func circle(around center: CGPoint, radius: CGFloat) -> Path {
		Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
	}
}

private struct ChartGeometry: Equatable {
	let center: CGPoint
	let innerRadius: CGFloat
	let outerRadius: CGFloat
	let ringWidth: CGFloat

	init(size: CGSize, maxDepth: Int) {
		let radius = min(size.width, size.height) / 2 - 4
		center = CGPoint(x: size.width / 2, y: size.height / 2)
		innerRadius = radius * 0.26
		outerRadius = radius
		ringWidth = (radius - innerRadius) / CGFloat(max(1, maxDepth))
	}
}
