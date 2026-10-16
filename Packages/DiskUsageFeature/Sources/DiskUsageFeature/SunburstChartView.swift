import AppUI
import SwiftUI

/// The sunburst: the folder on screen at the centre, its contents in rings around it, largest
/// first clockwise from the top. Hovering names a segment, clicking a folder opens it, clicking
/// the centre goes up.
struct SunburstChartView: View {
	let layout: SunburstLayout
	/// Whether clicking the centre can go up.
	let canGoUp: Bool
	@Binding
	var hovered: SunburstSegment?
	let selectedName: String?
	let onOpen: (DiskNode) -> Void
	let onGoUp: () -> Void
	let onSelect: (DiskNode?) -> Void

	@Environment(\.uiFontScale)
	private var uiFontScale
	@Environment(\.colorScheme)
	private var colorScheme

	var body: some View {
		GeometryReader { geometry in
			let geometry = ChartGeometry(size: geometry.size, maxDepth: layout.maxDepth)
			ZStack {
				Canvas { context, _ in
					draw(in: &context, geometry: geometry)
				}
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
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Disk usage of \(layout.center.name): \(layout.center.size.formatted(.byteCount(style: .file)))")
	}

	// MARK: - Drawing

	private func draw(in context: inout GraphicsContext, geometry: ChartGeometry) {
		for segment in layout.segments {
			let path = arcPath(for: segment, geometry: geometry)
			let isHovered = hovered?.id == segment.id
			let isSelected = selectedName != nil && segment.ancestry.first?.name == selectedName
			var color = color(of: segment)
			if let hovered, !isHovered, !isRelated(segment, to: hovered) {
				color = color.opacity(0.45)
			}
			context.fill(path, with: .color(color))
			if isHovered || isSelected {
				context.stroke(path, with: .color(.primary.opacity(isHovered ? 0.9 : 0.6)), lineWidth: isHovered ? 2 : 1.5)
			}
			else {
				context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1)
			}
		}
		let innerCircle = Path(ellipseIn: CGRect(
			x: geometry.center.x - geometry.innerRadius,
			y: geometry.center.y - geometry.innerRadius,
			width: geometry.innerRadius * 2,
			height: geometry.innerRadius * 2
		))
		context.fill(innerCircle, with: .color(Color.primary.opacity(canGoUp ? 0.07 : 0.04)))
	}

	/// Segments on the same branch as the hovered one keep their full colour.
	private func isRelated(_ segment: SunburstSegment, to hovered: SunburstSegment) -> Bool {
		guard let hoveredNode = hovered.node else { return false }
		return segment.ancestry.contains(where: { $0 === hoveredNode }) || hovered.ancestry.contains(where: { $0 === segment.node })
	}

	private func arcPath(for segment: SunburstSegment, geometry: ChartGeometry) -> Path {
		let inner = geometry.innerRadius + CGFloat(segment.depth - 1) * geometry.ringWidth
		let outer = inner + geometry.ringWidth - 0.5
		// Radians from the top, clockwise; SwiftUI's angles grow clockwise from the right.
		let startAngle = Angle(radians: segment.start * 2 * .pi - .pi / 2)
		let endAngle = Angle(radians: segment.end * 2 * .pi - .pi / 2)
		var path = Path()
		path.addArc(center: geometry.center, radius: outer, startAngle: startAngle, endAngle: endAngle, clockwise: false)
		path.addArc(center: geometry.center, radius: inner, startAngle: endAngle, endAngle: startAngle, clockwise: true)
		path.closeSubpath()
		return path
	}

	private func color(of segment: SunburstSegment) -> Color {
		switch segment.content {
		case .rest:
			return Color.gray.opacity(0.35)
		case let .node(node):
			if node.isInaccessible {
				return Color.gray.opacity(0.5)
			}
			let depthFade = Double(segment.depth - 1) * 0.06
			let isFile = !node.isDirectory
			return Color(
				hue: SunburstLayout.hue(of: segment),
				saturation: max(0.25, (isFile ? 0.4 : 0.62) - depthFade),
				brightness: colorScheme == .dark ? min(1, 0.8 + depthFade) : max(0.6, 0.92 - depthFade)
			)
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
		if node.isDirectory, !node.isInaccessible, segment.depth == 1 {
			onOpen(node)
		}
		else if let topLevel = segment.ancestry.first {
			onSelect(topLevel)
		}
	}
}

private struct ChartGeometry {
	let center: CGPoint
	let innerRadius: CGFloat
	let ringWidth: CGFloat

	init(size: CGSize, maxDepth: Int) {
		let radius = min(size.width, size.height) / 2 - 4
		center = CGPoint(x: size.width / 2, y: size.height / 2)
		innerRadius = radius * 0.26
		ringWidth = (radius - innerRadius) / CGFloat(max(1, maxDepth))
	}
}
