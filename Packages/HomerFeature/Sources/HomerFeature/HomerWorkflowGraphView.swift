import AppKit
import AppUI
import SwiftUI
import UniformTypeIdentifiers

/// A LangGraph workflow drawn from its topology (`workflow-graph.tsx`, ADR-0073), laid out by
/// `HomerGraphLayout`. With a run's `status` the nodes take their state's tint and their sub
/// runs' command dots, the edges the run took are green, and a node with sub runs opens
/// `nodeDetails` in a popover; without one it is the workflow's bare structure, as on the
/// console's agent page. The drawing is `HomerWorkflowGraphDrawing`: edges in a `Canvas`, node
/// boxes as views over it, for tooltips and accessibility. Above the render cap `fallback` is
/// shown instead.
/// "Save as Image…" and "Copy Image" render the whole graph, not the part scrolled into view.
struct HomerWorkflowGraphView<NodeDetails: View, Fallback: View>: View {
	let topology: HomerLangGraphStatus.Topology
	var status: HomerLangGraphStatus?
	/// The tallest the graph gets before it scrolls.
	var maxHeight: CGFloat = 480
	/// The saved image's file name, without its extension.
	var imageName = "Workflow"
	@ViewBuilder
	let nodeDetails: (String) -> NodeDetails
	@ViewBuilder
	let fallback: () -> Fallback

	@Environment(\.uiFontScale)
	private var scale

	@State
	private var layout: LayoutState = .pending

	@State
	private var openNode: String?

	@Environment(\.colorScheme)
	private var colorScheme

	private enum LayoutState: Equatable {
		case pending
		case laidOut(HomerGraphLayout)
		case tooLarge
	}

	/// The layout depends on the topology and the text's size alone, so a status poll that only
	/// moves the nodes' states draws the same layout again.
	private struct LayoutKey: Hashable {
		var topology: HomerLangGraphStatus.Topology
		var scale: CGFloat
	}

	var body: some View {
		Group {
			switch layout {
			case .pending:
				ProgressView()
					.controlSize(.small)
					.frame(maxWidth: .infinity, alignment: .leading)
			case let .laidOut(layout):
				graph(layout)
			case .tooLarge:
				fallback()
			}
		}
		.task(id: LayoutKey(topology: topology, scale: scale)) {
			let sizes = Self.measure(topology, scale: scale)
			let topology = topology
			let laidOut = await Task.detached(priority: .userInitiated) {
				HomerGraphLayout.make(topology: topology, nodeSizes: sizes.nodes, labelSizes: sizes.labels)
			}.value
			layout = laidOut.map(LayoutState.laidOut) ?? .tooLarge
		}
	}

	// MARK: Measuring

	private static func nodeFont(scale: CGFloat) -> NSFont {
		.systemFont(ofSize: UIFontScale.pointSize(of: .callout) * scale)
	}

	/// The boxes as the console sizes them (`layout.ts`: the label plus 16 pt each side, at
	/// least 72 wide and 36 high, a terminal 56 by 28), measured in the font they are drawn
	/// with rather than estimated per character, and grown with the text size.
	private static func measure(
		_ topology: HomerLangGraphStatus.Topology,
		scale: CGFloat
	) -> (nodes: [String: CGSize], labels: [String: CGSize]) {
		let nodeFont = nodeFont(scale: scale)
		let labelFont = NSFont.systemFont(ofSize: HomerWorkflowGraphDrawing.labelFontSize(scale: scale))
		var nodes: [String: CGSize] = [:]
		for node in topology.nodes {
			let (label, isTerminal) = HomerGraphLayout.nodeLabel(node.id)
			let text = (label as NSString).size(withAttributes: [.font: nodeFont])
			nodes[node.id] = CGSize(
				width: max((isTerminal ? 56 : 72) * scale, ceil(text.width) + 32),
				height: max((isTerminal ? 28 : 36) * scale, ceil(text.height) + (isTerminal ? 10 : 18))
			)
		}
		var labels: [String: CGSize] = [:]
		for label in topology.edges.compactMap(HomerGraphLayout.edgeLabel) {
			let text = (label as NSString).size(withAttributes: [.font: labelFont])
			labels[label] = CGSize(width: ceil(text.width) + 8, height: max(16 * scale, ceil(text.height) + 2))
		}
		return (nodes, labels)
	}

	// MARK: Drawing

	private func graph(_ layout: HomerGraphLayout) -> some View {
		VStack(spacing: 10) {
			ScrollView([.horizontal, .vertical]) {
				HomerWorkflowGraphDrawing(layout: layout, status: status)
					.overlay(alignment: .topLeading) {
						nodeButtons(layout)
					}
					// Centred when narrower than the view.
					.containerRelativeFrame(.horizontal) { length, _ in max(length, layout.size.width) }
			}
			// As high as the graph up to `maxHeight`, and less where there is less room.
			.frame(minHeight: 0, idealHeight: min(layout.size.height, maxHeight), maxHeight: min(layout.size.height, maxHeight))
			.contextMenu {
				imageActions(layout)
			}
			HStack(spacing: 16) {
				edgeLegend
				Spacer(minLength: 0)
				Menu {
					imageActions(layout)
				} label: {
					Label("Export", systemImage: "square.and.arrow.up")
				}
				.menuStyle(.borderlessButton)
				.fixedSize()
				.help("Save or copy the whole graph as an image")
			}
		}
		.padding(12)
		.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
		.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
	}

	/// Clear buttons over the nodes with sub runs, each opening them in a popover — as the console
	/// lays its popover triggers over the drawn graph. The drawing stays the same view the
	/// saved image renders.
	private func nodeButtons(_ layout: HomerGraphLayout) -> some View {
		ZStack(alignment: .topLeading) {
			ForEach(layout.nodes.filter { !$0.isTerminal && !(status?.subs?[$0.id]?.isEmpty ?? true) }) { node in
				let shape = RoundedRectangle(cornerRadius: 8)
				Button {
					openNode = node.id
				} label: {
					Color.clear
						.contentShape(shape)
				}
				.buttonStyle(.plain)
				.help("\(node.id): show its runs")
				.accessibilityLabel("Show the runs of \(node.id)")
				.popover(
					isPresented: Binding(
						get: { openNode == node.id },
						set: { isPresented in
							if !isPresented, openNode == node.id {
								openNode = nil
							}
						}
					),
					arrowEdge: .bottom
				) {
					nodeDetails(node.id)
				}
				.frame(width: node.frame.width, height: node.frame.height)
				.position(x: node.frame.midX, y: node.frame.midY)
			}
		}
		.frame(width: layout.size.width, height: layout.size.height)
	}

	// MARK: Image

	@ViewBuilder
	private func imageActions(_ layout: HomerGraphLayout) -> some View {
		Button {
			saveImage(layout)
		} label: {
			Label("Save as Image…", systemImage: "square.and.arrow.down")
		}
		Button {
			copyImage(layout)
		} label: {
			Label("Copy Image", systemImage: "doc.on.doc")
		}
	}

	private func pngData(_ layout: HomerGraphLayout) -> Data? {
		HomerWorkflowGraphDrawing.pngData(layout: layout, status: status, scale: scale, colorScheme: colorScheme)
	}

	private func saveImage(_ layout: HomerGraphLayout) {
		guard let data = pngData(layout) else {
			NSSound.beep()
			return
		}
		let panel = NSSavePanel()
		panel.allowedContentTypes = [.png]
		panel.canCreateDirectories = true
		panel.nameFieldStringValue = HomerWorkflowGraphDrawing.fileName(imageName)
		panel.begin { response in
			guard response == .OK, let url = panel.url else {
				return
			}
			do {
				try data.write(to: url, options: .atomic)
			}
			catch {
				NSAlert(error: error).runModal()
			}
		}
	}

	private func copyImage(_ layout: HomerGraphLayout) {
		guard let data = pngData(layout) else {
			NSSound.beep()
			return
		}
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setData(data, forType: .png)
	}

	private var edgeLegend: some View {
		HomerFlowLayout(spacing: 16) {
			legendEntry("fixed edge", color: .secondary, lineWidth: 1.25, dashed: false)
			legendEntry("conditional edge", color: .secondary, lineWidth: 1.25, dashed: true)
			if status?.traversed != nil {
				legendEntry("taken path", color: .green, lineWidth: 2, dashed: false)
			}
		}
		.scaledFont(.caption)
		.foregroundStyle(.secondary)
	}

	private func legendEntry(_ title: String, color: Color, lineWidth: CGFloat, dashed: Bool) -> some View {
		HStack(spacing: 6) {
			Path { path in
				path.move(to: CGPoint(x: 0, y: 3))
				path.addLine(to: CGPoint(x: 20, y: 3))
			}
			.stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [4, 3] : []))
			.frame(width: 20, height: 6)
			Text(title)
		}
	}
}

extension HomerWorkflowGraphView where NodeDetails == EmptyView {
	/// The workflow's structure alone.
	init(
		topology: HomerLangGraphStatus.Topology,
		maxHeight: CGFloat = 480,
		imageName: String,
		@ViewBuilder fallback: @escaping () -> Fallback
	) {
		self.init(
			topology: topology,
			status: nil,
			maxHeight: maxHeight,
			imageName: imageName,
			nodeDetails: { _ in EmptyView() },
			fallback: fallback
		)
	}
}

/// A laid-out workflow as drawn — the edges in a `Canvas`, the node boxes over them — at the
/// layout's own size. The graph view shows it scrolled with buttons over it; the saved and copied
/// image is this view rendered whole.
struct HomerWorkflowGraphDrawing: View {
	let layout: HomerGraphLayout
	var status: HomerLangGraphStatus?

	@Environment(\.uiFontScale)
	private var scale

	/// The image's pixels per point: sharp on a Retina screen and in a document.
	static let imageScale: CGFloat = 2
	/// Room around the graph in the image.
	static let imagePadding: CGFloat = 16

	static func labelFontSize(scale: CGFloat) -> CGFloat {
		UIFontScale.pointSize(of: .caption) * scale
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			edges
			ForEach(layout.nodes) { node in
				HomerWorkflowNodeBox(
					node: node,
					tint: node.isTerminal ? nil : status.flatMap { HomerWorkflowNodeTint(status: $0, node: node.id) },
					commandStates: status?.subs?[node.id]?.flatMap { ($0.commands ?? []).map(\.state) } ?? []
				)
				.help(node.id)
				.frame(width: node.frame.width, height: node.frame.height)
				.position(x: node.frame.midX, y: node.frame.midY)
			}
		}
		.frame(width: layout.size.width, height: layout.size.height)
	}

	/// The whole graph as a PNG on the graph's background, in the given appearance and text size.
	/// Twice the pixels of its points, marked as such so it opens at the graph's size.
	@MainActor
	static func pngData(
		layout: HomerGraphLayout,
		status: HomerLangGraphStatus?,
		scale: CGFloat,
		colorScheme: ColorScheme
	) -> Data? {
		let renderer = ImageRenderer(
			content: HomerWorkflowGraphDrawing(layout: layout, status: status)
				.padding(imagePadding)
				.background(Color(nsColor: .textBackgroundColor))
				.environment(\.colorScheme, colorScheme)
				.environment(\.uiFontScale, scale)
		)
		renderer.scale = imageScale
		guard let image = renderer.cgImage else {
			return nil
		}
		let bitmap = NSBitmapImageRep(cgImage: image)
		bitmap.size = CGSize(
			width: layout.size.width + 2 * imagePadding,
			height: layout.size.height + 2 * imagePadding
		)
		return bitmap.representation(using: .png, properties: [:])
	}

	/// The saved image's file name: `/` and `:` cannot stand in one.
	static func fileName(_ name: String) -> String {
		String(name.map { $0 == "/" || $0 == ":" ? "-" : $0 }) + ".png"
	}

	private struct EdgeKey: Hashable {
		var source: String
		var target: String
	}

	private var edges: some View {
		let taken = Set((status?.traversed ?? []).map { EdgeKey(source: $0.source, target: $0.target) })
		let labelFont = Font.system(size: Self.labelFontSize(scale: scale))
		let background = Color(nsColor: .textBackgroundColor)
		let layout = layout
		return Canvas { context, _ in
			// Taken edges last, on top of the rest.
			let ordered = layout.edges.sorted { lhs, rhs in
				!taken.contains(EdgeKey(source: lhs.source, target: lhs.target))
					&& taken.contains(EdgeKey(source: rhs.source, target: rhs.target))
			}
			for edge in ordered {
				let isTaken = taken.contains(EdgeKey(source: edge.source, target: edge.target))
				let color = isTaken ? Color.green : Color.secondary
				context.stroke(
					Self.path(of: edge),
					with: .color(color),
					style: StrokeStyle(lineWidth: isTaken ? 2 : 1.25, dash: edge.isConditional ? [4, 3] : [])
				)
				if let arrowhead = Self.arrowhead(of: edge, size: isTaken ? 9 : 8) {
					context.fill(arrowhead, with: .color(color))
				}
			}
			for edge in layout.edges {
				guard let label = edge.label, let frame = edge.labelFrame else {
					continue
				}
				context.fill(RoundedRectangle(cornerRadius: 4).path(in: frame), with: .color(background))
				context.draw(
					Text(label).font(labelFont).foregroundStyle(.secondary),
					at: CGPoint(x: frame.midX, y: frame.midY)
				)
			}
		}
		.frame(width: layout.size.width, height: layout.size.height)
		.accessibilityHidden(true)
	}

	/// Straight through the edge's points, rounded at each bend (`smoothPath`); a self-loop is
	/// its cubic curve.
	static func path(of edge: HomerGraphLayout.Edge) -> Path {
		var path = Path()
		let points = edge.points
		guard let first = points.first else {
			return path
		}
		path.move(to: first)
		if edge.isSelfLoop, points.count == 4 {
			path.addCurve(to: points[3], control1: points[1], control2: points[2])
			return path
		}
		for index in points.indices.dropFirst().dropLast() {
			let next = points[index + 1]
			let middle = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
			path.addQuadCurve(to: middle, control: points[index])
		}
		if points.count > 1 {
			path.addLine(to: points[points.count - 1])
		}
		return path
	}

	/// The arrow at the target's end, along the edge's last stretch.
	static func arrowhead(of edge: HomerGraphLayout.Edge, size: CGFloat) -> Path? {
		guard edge.points.count > 1 else {
			return nil
		}
		let tip = edge.points[edge.points.count - 1]
		let from = edge.points[edge.points.count - 2]
		let length = hypot(tip.x - from.x, tip.y - from.y)
		guard length > 0 else {
			return nil
		}
		let direction = CGPoint(x: (tip.x - from.x) / length, y: (tip.y - from.y) / length)
		let base = CGPoint(x: tip.x - direction.x * size, y: tip.y - direction.y * size)
		let half = size / 2
		var path = Path()
		path.move(to: tip)
		path.addLine(to: CGPoint(x: base.x - direction.y * half, y: base.y + direction.x * half))
		path.addLine(to: CGPoint(x: base.x + direction.y * half, y: base.y - direction.x * half))
		path.closeSubpath()
		return path
	}
}

/// A node's state as its box shows it (`workflow-status.tsx`'s `nodeTint`).
enum HomerWorkflowNodeTint: Equatable {
	case done
	case failed
	case parked
	case pending
	/// Parked, and its sub runs have all finished: the agents' work is done, but the join has not
	/// resolved.
	case subsFinished

	init?(status: HomerLangGraphStatus, node: String) {
		if status.subsFinished(node: node) {
			self = .subsFinished
			return
		}
		switch status.nodeStates?[node] {
		case "done": self = .done
		case "failed": self = .failed
		case "parked": self = .parked
		case "pending": self = .pending
		default: return nil
		}
	}

	var fill: Color {
		switch self {
		case .done, .subsFinished: .green
		case .failed: .red
		case .parked: .orange
		case .pending: .blue
		}
	}

	var stroke: Color {
		self == .subsFinished ? .orange : fill
	}
}

/// A node's box: its tint (or the plain card colour of a node the run has not reached), its
/// name, and its sub runs' command dots along the bottom edge. Start and end are dashed pills.
private struct HomerWorkflowNodeBox: View {
	let node: HomerGraphLayout.Node
	let tint: HomerWorkflowNodeTint?
	let commandStates: [String]

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: node.isTerminal ? node.frame.height / 2 : 8)
		ZStack {
			shape
				.fill(node.isTerminal ? Color.clear : tint.map { $0.fill.opacity(0.15) } ?? Color(nsColor: .controlBackgroundColor))
			shape
				.strokeBorder(strokeColor, style: StrokeStyle(lineWidth: 1.5, dash: dash))
			Text(node.label)
				.scaledFont(.callout)
				.foregroundStyle(node.isTerminal ? .secondary : .primary)
				.lineLimit(1)
			ForEach(Array(HomerWorkflowCommandDotRow.dots(commandStates, width: node.frame.width).enumerated()), id: \.offset) { _, dot in
				Circle()
					.fill(HomerCommandDots.color(dot.state))
					.opacity(dot.state == "running" ? 0.6 : 1)
					.frame(width: HomerWorkflowCommandDotRow.radius * 2, height: HomerWorkflowCommandDotRow.radius * 2)
					.position(x: dot.x, y: node.frame.height - HomerWorkflowCommandDotRow.bottomInset)
			}
		}
		.contentShape(shape)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(node.id)
		.accessibilityValue(accessibilityState)
	}

	private var strokeColor: Color {
		if node.isTerminal {
			return .secondary
		}
		return tint?.stroke ?? Color.secondary.opacity(0.45)
	}

	private var dash: [CGFloat] {
		if node.isTerminal {
			return [3, 3]
		}
		return tint == .subsFinished ? [4, 3] : []
	}

	private var accessibilityState: String {
		switch tint {
		case .done: "done"
		case .failed: "failed"
		case .parked: "parked"
		case .pending: "pending"
		case .subsFinished: "parked, sub runs finished"
		case nil: ""
		}
	}
}

/// Where a node's command dots go (`workflow-dots.ts`'s `dotRow`): centred along the bottom,
/// squeezed down to `minSpacing`, and past that the oldest dropped — the newest and the running
/// ones say the most.
enum HomerWorkflowCommandDotRow {
	static let radius: CGFloat = 2.5
	static let bottomInset: CGFloat = 5
	private static let spacing: CGFloat = 7
	private static let edgeInset: CGFloat = 4
	private static let minSpacing: CGFloat = 5.5

	static func dots(_ states: [String], width: CGFloat) -> [(state: String, x: CGFloat)] {
		guard !states.isEmpty else {
			return []
		}
		let usable = max(0, width - 2 * edgeInset)
		var row = states
		var gap = row.count > 1 ? min(spacing, usable / CGFloat(row.count - 1)) : 0
		if row.count > 1, gap < minSpacing {
			let maxDots = max(1, Int(floor(usable / minSpacing)) + 1)
			row = Array(row.suffix(maxDots))
			gap = row.count > 1 ? min(spacing, usable / CGFloat(row.count - 1)) : 0
		}
		let start = width / 2 - CGFloat(row.count - 1) * gap / 2
		return row.enumerated().map { ($0.element, start + CGFloat($0.offset) * gap) }
	}
}
