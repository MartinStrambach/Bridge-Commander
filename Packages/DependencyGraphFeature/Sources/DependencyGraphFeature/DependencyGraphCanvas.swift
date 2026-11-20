import AppKit
import AppUI
import SwiftUI

/// The graph itself: one `Canvas` drawing every edge and node, panned and zoomed by an AppKit
/// overlay (`GraphInteractionLayer`) that turns clicks, drags, scrolls and pinches into callbacks.
///
/// Pan and zoom are view state: they are how the user looks at the graph, not what it is.
struct DependencyGraphCanvas: View {
	let graph: PlatformGraph
	let layout: GraphLayout
	let layoutRevision: Int
	let changes: ModuleChanges?
	let selectedID: String?
	let showsIndirectEdges: Bool
	let onSelect: (String?) -> Void

	@State private var zoom: CGFloat = 1
	/// Where the graph's origin sits in the view.
	@State private var offset: CGSize = .zero
	@State private var viewSize: CGSize = .zero
	@State private var fittedRevision: Int?
	@State private var hoveredID: String?

	static let minimumZoom: CGFloat = 0.05
	static let maximumZoom: CGFloat = 3

	var body: some View {
		let focus = Focus(graph: graph, selectedID: selectedID)
		GeometryReader { proxy in
			GraphDrawing(
				graph: graph,
				layout: layout,
				changes: changes,
				selectedID: selectedID,
				hoveredID: hoveredID,
				focus: focus,
				showsIndirectEdges: showsIndirectEdges,
				zoom: zoom,
				offset: offset
			)
			.overlay {
				GraphInteractionLayer(
					onPan: { delta in
						offset.width += delta.width
						offset.height += delta.height
					},
					onZoom: zoom(by:around:),
					onClick: { point in
						onSelect(node(at: point))
					},
					onHover: { point in
						hoveredID = point.flatMap(node(at:))
					}
				)
			}
			.onChange(of: proxy.size, initial: true) { _, size in
				viewSize = size
				fitIfNeeded()
			}
		}
		.background(Color(nsColor: .textBackgroundColor))
		.overlay(alignment: .bottomTrailing) {
			zoomControls
				.padding(10)
		}
		.overlay(alignment: .bottomLeading) {
			hoverLabel
				.padding(10)
		}
		.onChange(of: layoutRevision) {
			fitIfNeeded()
		}
		.onChange(of: selectedID) {
			if let selectedID {
				reveal(selectedID)
			}
		}
	}

	// MARK: - Focus

	/// The selected module with everything it reaches either way; the rest is dimmed.
	struct Focus {
		let selectedID: String
		let dependencies: Set<String>
		let dependents: Set<String>

		init?(graph: PlatformGraph, selectedID: String?) {
			guard let selectedID else {
				return nil
			}
			self.selectedID = selectedID
			dependencies = graph.transitiveDependencies(of: selectedID)
			dependents = graph.transitiveDependents(of: selectedID)
		}

		func contains(_ id: String) -> Bool {
			id == selectedID || dependencies.contains(id) || dependents.contains(id)
		}
	}

	// MARK: - Overlays

	private var zoomControls: some View {
		HStack(spacing: 4) {
			Button {
				zoom(by: 1 / 1.25, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
			} label: {
				Image(systemName: "minus.magnifyingglass")
			}
			.help("Zoom out (pinch, or ⌘-scroll)")

			Button {
				fit()
			} label: {
				Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
			}
			.help("Fit the graph to the window")

			Button {
				zoom(by: 1.25, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
			} label: {
				Image(systemName: "plus.magnifyingglass")
			}
			.help("Zoom in (pinch, or ⌘-scroll)")
		}
		.buttonStyle(.scaledBordered)
	}

	@ViewBuilder
	private var hoverLabel: some View {
		if let hoveredID, let module = graph.module(withID: hoveredID) {
			VStack(alignment: .leading, spacing: 2) {
				Text(module.name)
					.scaledFont(.callout)
					.fontWeight(.semibold)
				Text(hoverDetail(for: module))
					.scaledFont(.caption)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
			.allowsHitTesting(false)
		}
	}

	private func hoverDetail(for module: DependencyModule) -> String {
		var parts = [module.kind.title]
		if graph.boundaryModuleIDs.contains(module.id) {
			parts.append("other platform")
		}
		if let count = changes?.changedFileCounts[module.id] {
			parts.append(changes?.status(of: module.id) == .new ? "new, \(count) files" : "\(count) changed files")
		}
		parts.append("\(graph.dependencies[module.id]?.count ?? 0) dependencies")
		parts.append("used by \(graph.dependents[module.id]?.count ?? 0)")
		return parts.joined(separator: " · ")
	}

	// MARK: - Geometry

	private func node(at viewPoint: CGPoint) -> String? {
		let point = CGPoint(x: (viewPoint.x - offset.width) / zoom, y: (viewPoint.y - offset.height) / zoom)
		return layout.frames.first { $0.value.contains(point) }?.key
	}

	private func zoom(by factor: CGFloat, around anchor: CGPoint) {
		let newZoom = min(max(zoom * factor, Self.minimumZoom), Self.maximumZoom)
		let scale = newZoom / zoom
		// Keep the graph point under the anchor where it is.
		offset = CGSize(
			width: anchor.x - (anchor.x - offset.width) * scale,
			height: anchor.y - (anchor.y - offset.height) * scale
		)
		zoom = newZoom
	}

	private func fitIfNeeded() {
		guard fittedRevision != layoutRevision, viewSize.width > 0, viewSize.height > 0, layout.size != .zero else {
			return
		}
		fit()
	}

	/// The whole graph in view, never magnified past 100 %.
	private func fit() {
		guard viewSize.width > 0, viewSize.height > 0, layout.size.width > 0, layout.size.height > 0 else {
			return
		}

		fittedRevision = layoutRevision
		zoom = min(max(min(viewSize.width / layout.size.width, viewSize.height / layout.size.height), Self.minimumZoom), 1)
		offset = CGSize(
			width: (viewSize.width - layout.size.width * zoom) / 2,
			height: (viewSize.height - layout.size.height * zoom) / 2
		)
	}

	/// Centres a module that is off screen, zooming in far enough to read it.
	private func reveal(_ id: String) {
		guard let frame = layout.frames[id] else {
			return
		}

		let onScreen = CGRect(
			x: frame.minX * zoom + offset.width,
			y: frame.minY * zoom + offset.height,
			width: frame.width * zoom,
			height: frame.height * zoom
		)
		let isVisible = CGRect(origin: .zero, size: viewSize).contains(onScreen)
		guard !isVisible || zoom < 0.4 else {
			return
		}

		zoom = max(zoom, 0.6)
		offset = CGSize(
			width: viewSize.width / 2 - frame.midX * zoom,
			height: viewSize.height / 2 - frame.midY * zoom
		)
	}
}

// MARK: - Drawing

/// Every edge and node in one `Canvas`, at the given zoom and offset, culled to what is on
/// screen. Edges are batched into one path per style.
struct GraphDrawing: View {
	let graph: PlatformGraph
	let layout: GraphLayout
	let changes: ModuleChanges?
	let selectedID: String?
	let hoveredID: String?
	let focus: DependencyGraphCanvas.Focus?
	let showsIndirectEdges: Bool
	let zoom: CGFloat
	let offset: CGSize

	var body: some View {
		Canvas { context, size in
			draw(in: &context, size: size)
		}
	}

	private func draw(in context: inout GraphicsContext, size: CGSize) {
		// Band labels are drawn in view points afterwards, pinned to the left edge.
		let labelContext = context
		context.translateBy(x: offset.width, y: offset.height)
		context.scaleBy(x: zoom, y: zoom)
		// What is on screen, in graph points, with a margin for the edges' curves.
		let visible = CGRect(
			x: -offset.width / zoom,
			y: -offset.height / zoom,
			width: size.width / zoom,
			height: size.height / zoom
		)
		.insetBy(dx: -60, dy: -60)
		// At least about a pixel wide however far out the graph is zoomed.
		let lineWidth = max(1, 0.8 / zoom)

		// Every other band striped, across the whole visible width.
		for (index, band) in layout.bands.enumerated() where index.isMultiple(of: 2) {
			context.fill(
				Path(CGRect(x: visible.minX, y: band.minY, width: visible.width, height: band.maxY - band.minY)),
				with: .color(Color.primary.opacity(0.035))
			)
		}

		var plain = Path()
		var test = Path()
		var towardDependencies = Path()
		var towardDependents = Path()
		var faded = Path()
		for edge in graph.edges {
			// An implied edge is drawn on request, or when it is the selected module's own.
			if !showsIndirectEdges, graph.indirectEdges.contains(edge),
			   edge.from != focus?.selectedID, edge.to != focus?.selectedID {
				continue
			}
			guard let from = layout.frames[edge.from], let to = layout.frames[edge.to],
			      from.union(to).intersects(visible)
			else {
				continue
			}

			let start = CGPoint(x: from.midX, y: from.maxY)
			let end = CGPoint(x: to.midX, y: to.minY)
			let bend = max(abs(end.y - start.y) / 2, 30)
			var path = Path()
			path.move(to: start)
			path.addCurve(
				to: end,
				control1: CGPoint(x: start.x, y: start.y + bend),
				control2: CGPoint(x: end.x, y: end.y - bend)
			)
			path.move(to: CGPoint(x: end.x - 4, y: end.y - 7))
			path.addLine(to: end)
			path.addLine(to: CGPoint(x: end.x + 4, y: end.y - 7))

			if let focus {
				let fromIsSource = edge.from == focus.selectedID || focus.dependencies.contains(edge.from)
				let toIsSink = edge.to == focus.selectedID || focus.dependents.contains(edge.to)
				if fromIsSource, focus.dependencies.contains(edge.to) {
					towardDependencies.addPath(path)
				}
				else if toIsSink, focus.dependents.contains(edge.from) {
					towardDependents.addPath(path)
				}
				else {
					faded.addPath(path)
				}
			}
			else if edge.isTest {
				test.addPath(path)
			}
			else {
				plain.addPath(path)
			}
		}

		let edgeColor = Color.secondary
		context.stroke(faded, with: .color(edgeColor.opacity(0.06)), lineWidth: lineWidth)
		context.stroke(plain, with: .color(edgeColor.opacity(0.3)), lineWidth: lineWidth)
		context.stroke(
			test,
			with: .color(edgeColor.opacity(0.3)),
			style: StrokeStyle(lineWidth: lineWidth, dash: [4 * lineWidth, 3 * lineWidth])
		)
		context.stroke(towardDependencies, with: .color(GraphPalette.dependency), lineWidth: lineWidth * 1.6)
		context.stroke(towardDependents, with: .color(GraphPalette.dependent), lineWidth: lineWidth * 1.6)

		// Text below ~5 pt on screen is unreadable; boxes alone keep the shape.
		let drawsText = zoom >= 0.4
		for module in graph.modules {
			guard let frame = layout.frames[module.id], frame.intersects(visible) else {
				continue
			}
			drawNode(module, frame: frame, in: &context, focus: focus, drawsText: drawsText, lineWidth: lineWidth)
		}

		drawBandLabels(in: labelContext)
	}

	private func drawBandLabels(in context: GraphicsContext) {
		for band in layout.bands {
			let top = band.minY * zoom + offset.height
			let height = (band.maxY - band.minY) * zoom
			guard height >= 16 else {
				continue
			}
			context.draw(
				Text(band.title)
					.font(.system(size: 10, weight: .medium))
					.foregroundStyle(Color.secondary),
				at: CGPoint(x: 8, y: top + 6),
				anchor: .topLeading
			)
		}
	}

	private func drawNode(
		_ module: DependencyModule,
		frame: CGRect,
		in context: inout GraphicsContext,
		focus: DependencyGraphCanvas.Focus?,
		drawsText: Bool,
		lineWidth: CGFloat
	) {
		let isBoundary = graph.boundaryModuleIDs.contains(module.id)
		let status = changes?.status(of: module.id)
		let isSelected = module.id == selectedID
		let isHovered = module.id == hoveredID
		var alpha: Double = focus.map { $0.contains(module.id) ? 1 : 0.2 } ?? 1
		if isBoundary {
			alpha *= 0.6
		}

		let shape = Path(roundedRect: frame, cornerRadius: 8)
		context.fill(shape, with: .color(Color(nsColor: .controlBackgroundColor).opacity(alpha)))
		if let status {
			context.fill(shape, with: .color(GraphPalette.color(for: status).opacity(0.2 * alpha)))
		}

		// The platform's colour as a stripe down the left edge.
		let stripe = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
			.path(in: CGRect(x: frame.minX, y: frame.minY, width: 5, height: frame.height))
		context.fill(stripe, with: .color(GraphPalette.color(for: module.kind).opacity(alpha)))

		let borderColor: Color
		let borderWidth: CGFloat
		if isSelected {
			borderColor = .accentColor
			borderWidth = 3
		}
		else if let status {
			borderColor = GraphPalette.color(for: status).opacity(alpha)
			borderWidth = 2
		}
		else {
			borderColor = Color.secondary.opacity((isHovered ? 0.9 : 0.45) * alpha)
			borderWidth = isHovered ? 1.5 : 1
		}
		context.stroke(
			shape,
			with: .color(borderColor),
			style: StrokeStyle(
				lineWidth: max(borderWidth, lineWidth),
				dash: isBoundary ? [5, 3] : []
			)
		)

		guard drawsText else {
			return
		}

		let textX = frame.minX + 14
		context.draw(
			Text(module.title)
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(Color.primary.opacity(alpha)),
			at: CGPoint(x: textX, y: frame.midY - 7),
			anchor: .leading
		)
		context.draw(
			Text(module.subtitle)
				.font(.system(size: 9.5))
				.foregroundStyle(Color.secondary.opacity(alpha)),
			at: CGPoint(x: textX, y: frame.midY + 8),
			anchor: .leading
		)
	}

}

// MARK: - Palette

enum GraphPalette {
	static let dependency = Color.blue
	static let dependent = Color.pink

	static func color(for status: ModuleChanges.Status) -> Color {
		switch status {
		case .new: .green
		case .changed: .orange
		}
	}

	static func color(for kind: ModuleKind) -> Color {
		switch kind {
		case .kmp: .purple
		case .android: .teal
		case .jvm: .brown
		case .iosFramework, .iosExtension: .indigo
		}
	}
}

// MARK: - Interaction

/// A transparent AppKit view over the canvas: a click (no drag) selects, a drag or a two-finger
/// scroll pans, a pinch or ⌘-scroll zooms around the pointer, and pointer moves report hover.
/// AppKit rather than SwiftUI gestures, because SwiftUI has no scroll-wheel event on macOS.
struct GraphInteractionLayer: NSViewRepresentable {
	let onPan: (CGSize) -> Void
	let onZoom: (CGFloat, CGPoint) -> Void
	let onClick: (CGPoint) -> Void
	let onHover: (CGPoint?) -> Void

	func makeNSView(context: Context) -> GraphInteractionView {
		let view = GraphInteractionView()
		update(view)
		return view
	}

	func updateNSView(_ view: GraphInteractionView, context: Context) {
		update(view)
	}

	private func update(_ view: GraphInteractionView) {
		view.onPan = onPan
		view.onZoom = onZoom
		view.onClick = onClick
		view.onHover = onHover
	}
}

final class GraphInteractionView: NSView {
	var onPan: (CGSize) -> Void = { _ in }
	var onZoom: (CGFloat, CGPoint) -> Void = { _, _ in }
	var onClick: (CGPoint) -> Void = { _ in }
	var onHover: (CGPoint?) -> Void = { _ in }

	private var dragStart: CGPoint?
	private var isDragging = false

	override var isFlipped: Bool { true }

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(
			rect: .zero,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseDown(with event: NSEvent) {
		dragStart = location(of: event)
		isDragging = false
	}

	override func mouseDragged(with event: NSEvent) {
		guard let dragStart else {
			return
		}

		let point = location(of: event)
		if !isDragging, hypot(point.x - dragStart.x, point.y - dragStart.y) > 3 {
			isDragging = true
			NSCursor.closedHand.push()
		}
		if isDragging {
			onPan(CGSize(width: event.deltaX, height: event.deltaY))
		}
	}

	override func mouseUp(with event: NSEvent) {
		if isDragging {
			NSCursor.pop()
		}
		else {
			onClick(location(of: event))
		}
		dragStart = nil
		isDragging = false
	}

	override func scrollWheel(with event: NSEvent) {
		let point = location(of: event)
		if event.modifierFlags.contains(.command) {
			let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
			onZoom(exp(delta * 0.01), point)
			return
		}

		let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
		onPan(CGSize(width: event.scrollingDeltaX * scale, height: event.scrollingDeltaY * scale))
	}

	override func magnify(with event: NSEvent) {
		onZoom(1 + event.magnification, location(of: event))
	}

	override func mouseMoved(with event: NSEvent) {
		onHover(location(of: event))
	}

	override func mouseExited(with event: NSEvent) {
		onHover(nil)
	}

	private func location(of event: NSEvent) -> CGPoint {
		convert(event.locationInWindow, from: nil)
	}
}
