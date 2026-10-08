import CoreGraphics
import Foundation

/// A LangGraph workflow's topology laid out top to bottom for drawing — the console's
/// `lib/langgraph/layout.ts`, which hands the graph to dagre. This is the same layered
/// (Sugiyama) layout done natively, with dagre's conventions so the two read alike:
///
/// 1. Cycles are broken by turning around the edges a depth-first search finds going back to a
///    node still on its stack (dagre's `dfsFAS`); they are drawn the right way round again.
/// 2. Every edge spans at least two ranks (dagre doubles `minlen` and halves `ranksep`), so the
///    odd rank between two nodes' ranks holds the edge's label. Ranks start as the longest path
///    from the sources; then each node moves, while that shortens the edges, as close to its
///    predecessors or successors as it can — whichever side has more edges.
/// 3. Edges longer than one rank become chains of dummy vertices, one per rank, the label's
///    dummy as wide and high as the label.
/// 4. The order within each rank starts from a depth-first walk, then barycenter sweeps up and
///    down reduce the crossings, as dagre's do; the best order seen is kept.
/// 5. The x positions are dagre's too, Brandes–Köpf: vertices line up in vertical blocks under
///    their median neighbours, a long edge's dummies before anything crossing them, so chains
///    and long edges run straight; four such alignments are compacted and balanced.
///
/// Self-loops are not laid out but drawn on the node's right, as the console draws them, and
/// the node's box is widened for them. Above the console's render cap there is no layout.
public nonisolated struct HomerGraphLayout: Equatable, Sendable {
	public nonisolated struct Node: Equatable, Sendable, Identifiable {
		public var id: String
		/// The id, truncated; `start` and `end` for the graph's terminals.
		public var label: String
		/// `__start__` or `__end__`, drawn as a dashed pill.
		public var isTerminal: Bool
		public var frame: CGRect
	}

	public nonisolated struct Edge: Equatable, Sendable, Identifiable {
		/// The edge's index in the topology.
		public var id: Int
		public var source: String
		public var target: String
		/// Truncated; nil for none.
		public var label: String?
		public var isConditional: Bool
		/// A self-loop's `points` are a cubic curve's start, two control points and end.
		public var isSelfLoop: Bool
		/// From the source's box to the target's, through a point per rank in between: a
		/// polyline to be drawn rounded at each interior point.
		public var points: [CGPoint]
		public var labelFrame: CGRect?
	}

	public var size: CGSize
	public var nodes: [Node]
	public var edges: [Edge]

	/// The console's render cap (`MAX_RENDER_NODES`, `MAX_RENDER_EDGES`), below the server's own.
	public static let maxNodes = 200
	public static let maxEdges = 300
	static let maxLabelCharacters = 40

	static let start = "__start__"
	static let end = "__end__"

	/// dagre's settings in the console (`nodesep`, `ranksep`, `edgesep`, `marginx`/`marginy`).
	static let nodeSeparation = 32.0
	static let rankSeparation = 44.0
	static let edgeSeparation = 16.0
	static let margin = 8.0
	// Self-loops, as `layout.ts` draws them: each further loop on a node reaches `loopStep`
	// further, so they nest.
	static let loopReach = 18.0
	static let loopStep = 8.0
	static let loopSpread = 7.0
	static let loopClearance = 8.0

	/// What a node's box says, and whether it is one of the graph's terminals.
	public static func nodeLabel(_ id: String) -> (label: String, isTerminal: Bool) {
		switch id {
		case start: ("start", true)
		case end: ("end", true)
		default: (truncatedLabel(id), false)
		}
	}

	/// Node ids and edge labels are agent-authored: a long one is cut with an ellipsis.
	public static func truncatedLabel(_ text: String) -> String {
		text.count > maxLabelCharacters ? String(text.prefix(maxLabelCharacters - 1)) + "…" : text
	}

	/// The topology's edges' labels as drawn: truncated, an empty one dropped.
	public static func edgeLabel(_ edge: HomerLangGraphStatus.Topology.Edge) -> String? {
		guard let label = edge.label, !label.isEmpty else {
			return nil
		}
		return truncatedLabel(label)
	}

	/// The layout, or nil above the render cap.
	///
	/// - Parameters:
	///   - nodeSizes: Each node's box by id; the view measures them in the font it draws with.
	///   - labelSizes: Each edge label's box by its text as `edgeLabel` gives it.
	public static func make(
		topology: HomerLangGraphStatus.Topology,
		nodeSizes: [String: CGSize],
		labelSizes: [String: CGSize]
	) -> HomerGraphLayout? {
		guard topology.nodes.count <= maxNodes, topology.edges.count <= maxEdges else {
			return nil
		}
		var builder = Builder(topology: topology, nodeSizes: nodeSizes, labelSizes: labelSizes)
		return builder.layout()
	}
}

// MARK: - The layered layout

private nonisolated struct Builder {
	struct Vertex {
		var width: Double
		var height: Double
		var isDummy: Bool
		var rank = 0
		var x = 0.0
		var y = 0.0
	}

	struct LayoutEdge {
		/// Index in the topology.
		var id: Int
		/// The edge's ends after cycle breaking: `from` is drawn above `to`.
		var from: Int
		var to: Int
		var isReversed = false
		var label: String?
		var labelSize: CGSize?
		var isConditional: Bool
		/// The dummy vertices between `from` and `to`, top down.
		var chain: [Int] = []
		var labelDummy: Int?
	}

	struct SelfLoop {
		var id: Int
		var label: String?
		var labelSize: CGSize
		var isConditional: Bool
	}

	/// Node ids, deduplicated, in the topology's order; vertex `i < ids.count` is node `i`.
	var ids: [String] = []
	var vertices: [Vertex] = []
	/// The real nodes' boxes as drawn, before any widening for self-loops.
	var drawnSizes: [CGSize] = []
	var edges: [LayoutEdge] = []
	var loops: [Int: [SelfLoop]] = [:]

	/// Each vertex's neighbours one rank up and one rank down.
	var up: [[Int]] = []
	var down: [[Int]] = []
	var layers: [[Int]] = []
	/// Each vertex's position within its layer.
	var order: [Int] = []

	init(topology: HomerLangGraphStatus.Topology, nodeSizes: [String: CGSize], labelSizes: [String: CGSize]) {
		var index: [String: Int] = [:]
		for node in topology.nodes where index[node.id] == nil {
			index[node.id] = ids.count
			ids.append(node.id)
			let size = nodeSizes[node.id] ?? CGSize(width: 72, height: 36)
			drawnSizes.append(size)
			vertices.append(Vertex(width: size.width, height: size.height, isDummy: false))
		}
		for (id, edge) in topology.edges.enumerated() {
			guard let source = index[edge.source], let target = index[edge.target] else {
				continue
			}
			let label = HomerGraphLayout.edgeLabel(edge)
			let labelSize = label.map { labelSizes[$0] ?? CGSize(width: Double($0.count) * 6.5 + 8, height: 16) }
			if source == target {
				loops[source, default: []].append(
					SelfLoop(id: id, label: label, labelSize: labelSize ?? .zero, isConditional: edge.conditional)
				)
			}
			else {
				edges.append(LayoutEdge(
					id: id,
					from: source,
					to: target,
					label: label,
					labelSize: labelSize,
					isConditional: edge.conditional
				))
			}
		}
	}

	mutating func layout() -> HomerGraphLayout {
		reserveRoomForLoops()
		breakCycles()
		assignRanks()
		insertDummies()
		orderLayers()
		assignX()
		assignY()
		return output()
	}

	// MARK: Self-loops

	static func outerReach(loopCount: Int) -> Double {
		HomerGraphLayout.loopReach + Double(loopCount - 1) * HomerGraphLayout.loopStep
	}

	static func loopLabelPitch(_ loops: [SelfLoop]) -> Double {
		(loops.filter { $0.label != nil }.map(\.labelSize.height).max() ?? 16) + 2
	}

	/// Widens a node's box by what its loops and their labels need beyond the node separation,
	/// and makes it as high as its stack of loop labels; the node is drawn at the box's left.
	mutating func reserveRoomForLoops() {
		for (vertex, nodeLoops) in loops {
			let labelWidths = nodeLoops.filter { $0.label != nil }.map(\.labelSize.width)
			let extent = Self.outerReach(loopCount: nodeLoops.count) + (labelWidths.max().map { 2 + $0 } ?? 0)
			let reserve = max(0, extent + HomerGraphLayout.loopClearance - HomerGraphLayout.nodeSeparation)
			vertices[vertex].width += reserve
			vertices[vertex].height = max(
				vertices[vertex].height,
				Double(labelWidths.count) * Self.loopLabelPitch(nodeLoops)
			)
		}
	}

	// MARK: 1. Cycles

	/// Turns around every edge a depth-first search, from the nodes in the topology's order,
	/// finds going back to a node on its stack.
	mutating func breakCycles() {
		let nodeCount = ids.count
		var outgoing = Array(repeating: [Int](), count: nodeCount)
		for (index, edge) in edges.enumerated() {
			outgoing[edge.from].append(index)
		}
		// 0 unvisited, 1 on the stack, 2 done.
		var visit = Array(repeating: 0, count: nodeCount)
		for root in 0 ..< nodeCount where visit[root] == 0 {
			var stack: [(vertex: Int, next: Int)] = [(root, 0)]
			visit[root] = 1
			while let (vertex, next) = stack.last {
				guard next < outgoing[vertex].count else {
					visit[vertex] = 2
					stack.removeLast()
					continue
				}
				stack[stack.count - 1].next += 1
				let index = outgoing[vertex][next]
				let target = edges[index].to
				switch visit[target] {
				case 0:
					visit[target] = 1
					stack.append((target, 0))
				case 1:
					let edge = edges[index]
					edges[index].isReversed = true
					edges[index].from = edge.to
					edges[index].to = edge.from
				default:
					break
				}
			}
		}
	}

	// MARK: 2. Ranks

	mutating func assignRanks() {
		let nodeCount = ids.count
		var predecessors = Array(repeating: [Int](), count: nodeCount)
		var successors = Array(repeating: [Int](), count: nodeCount)
		for edge in edges {
			successors[edge.from].append(edge.to)
			predecessors[edge.to].append(edge.from)
		}
		// The longest path from the sources, in topological order.
		var rank = Array(repeating: 0, count: nodeCount)
		var remaining = predecessors.map(\.count)
		var queue = (0 ..< nodeCount).filter { remaining[$0] == 0 }
		var head = 0
		while head < queue.count {
			let vertex = queue[head]
			head += 1
			for successor in successors[vertex] {
				rank[successor] = max(rank[successor], rank[vertex] + 2)
				remaining[successor] -= 1
				if remaining[successor] == 0 {
					queue.append(successor)
				}
			}
		}
		// Each move shortens the edges in total, so this ends; the bound is a safeguard.
		for _ in 0 ..< 100 {
			var moved = false
			for vertex in 0 ..< nodeCount {
				let incoming = predecessors[vertex].count
				let outgoing = successors[vertex].count
				let target: Int
				if incoming > outgoing {
					target = predecessors[vertex].map { rank[$0] + 2 }.max() ?? rank[vertex]
				}
				else if outgoing > incoming {
					target = successors[vertex].map { rank[$0] - 2 }.min() ?? rank[vertex]
				}
				else {
					continue
				}
				if target != rank[vertex] {
					rank[vertex] = target
					moved = true
				}
			}
			if !moved {
				break
			}
		}
		let lowest = rank.min() ?? 0
		for vertex in 0 ..< nodeCount {
			vertices[vertex].rank = rank[vertex] - lowest
		}
	}

	// MARK: 3. Dummies

	mutating func insertDummies() {
		up = Array(repeating: [], count: vertices.count)
		down = Array(repeating: [], count: vertices.count)
		for index in edges.indices {
			let edge = edges[index]
			let top = vertices[edge.from].rank
			let bottom = vertices[edge.to].rank
			let labelRank = edge.label == nil ? nil : top + (bottom - top) / 2
			var previous = edge.from
			for rank in top + 1 ..< bottom {
				let isLabel = rank == labelRank
				let size = isLabel ? edge.labelSize ?? .zero : .zero
				let dummy = vertices.count
				vertices.append(Vertex(width: size.width, height: size.height, isDummy: true, rank: rank))
				up.append([])
				down.append([])
				edges[index].chain.append(dummy)
				if isLabel {
					edges[index].labelDummy = dummy
				}
				connect(previous, dummy)
				previous = dummy
			}
			connect(previous, edge.to)
		}
	}

	private mutating func connect(_ upper: Int, _ lower: Int) {
		down[upper].append(lower)
		up[lower].append(upper)
	}

	// MARK: 4. Order

	mutating func orderLayers() {
		let rankCount = (vertices.map(\.rank).max() ?? -1) + 1
		layers = Array(repeating: [], count: rankCount)
		order = Array(repeating: 0, count: vertices.count)
		// A depth-first walk down from the vertices by rank puts each subtree together.
		var visited = Array(repeating: false, count: vertices.count)
		let roots = vertices.indices.sorted { (vertices[$0].rank, $0) < (vertices[$1].rank, $1) }
		for root in roots where !visited[root] {
			var stack = [root]
			while let vertex = stack.popLast() {
				guard !visited[vertex] else {
					continue
				}
				visited[vertex] = true
				order[vertex] = layers[vertices[vertex].rank].count
				layers[vertices[vertex].rank].append(vertex)
				stack.append(contentsOf: down[vertex].reversed())
			}
		}

		// dagre's sweeps: up and down by turns, ties broken toward the left for two sweeps and
		// toward the right for two, until four in a row bring no fewer crossings. An order as
		// good as the best replaces it, so the ties spread edges to both sides.
		var best = layers
		var bestCrossings = crossings()
		var iteration = 0
		var sinceImprovement = 0
		while sinceImprovement < 4 {
			let downward = !iteration.isMultiple(of: 2)
			let biasRight = iteration % 4 >= 2
			let ranks = downward ? Array(layers.indices.dropFirst()) : Array(layers.indices.dropLast().reversed())
			for rank in ranks {
				sortByBarycenter(rank: rank, neighbors: downward ? up : down, biasRight: biasRight)
			}
			let count = crossings()
			if count < bestCrossings {
				best = layers
				bestCrossings = count
				sinceImprovement = 0
			}
			else if count == bestCrossings {
				best = layers
			}
			iteration += 1
			sinceImprovement += 1
		}
		layers = best
		renumber()
	}

	private mutating func renumber() {
		for layer in layers {
			for (position, vertex) in layer.enumerated() {
				order[vertex] = position
			}
		}
	}

	/// Sorts the vertices that have neighbours in the fixed layer by their neighbours' mean
	/// position; the others keep their places.
	private mutating func sortByBarycenter(rank: Int, neighbors: [[Int]], biasRight: Bool) {
		let layer = layers[rank]
		let movable = layer.enumerated()
			.filter { !neighbors[$0.element].isEmpty }
			.map { position, vertex in
				let links = neighbors[vertex]
				let barycenter = Double(links.reduce(0) { $0 + order[$1] }) / Double(links.count)
				return (vertex: vertex, barycenter: barycenter, position: position)
			}
			.sorted { lhs, rhs in
				if lhs.barycenter != rhs.barycenter {
					return lhs.barycenter < rhs.barycenter
				}
				return biasRight ? lhs.position > rhs.position : lhs.position < rhs.position
			}
		var sorted = movable.makeIterator()
		var result = layer
		for position in result.indices where !neighbors[result[position]].isEmpty {
			result[position] = sorted.next()!.vertex
		}
		layers[rank] = result
		for (position, vertex) in result.enumerated() {
			order[vertex] = position
		}
	}

	/// Every crossing between consecutive layers: the inversions of the lower ends once the
	/// segments are sorted by their upper ends.
	func crossings() -> Int {
		var count = 0
		for rank in layers.indices.dropLast() {
			let ends = layers[rank]
				.flatMap { upper in down[upper].map { (order[upper], order[$0]) } }
				.sorted { $0 < $1 }
				.map(\.1)
			// A Fenwick tree over the lower layer's positions counts the ends seen so far that
			// lie right of each one.
			let size = layers[rank + 1].count
			var tree = Array(repeating: 0, count: size + 1)
			for (seen, end) in ends.enumerated() {
				var atOrLeft = 0
				var index = end + 1
				while index > 0 {
					atOrLeft += tree[index]
					index -= index & -index
				}
				count += seen - atOrLeft
				index = end + 1
				while index <= size {
					tree[index] += 1
					index += index & -index
				}
			}
		}
		return count
	}

	// MARK: 5. Coordinates

	/// The distance between the centres of two vertices side by side (dagre's `sep`).
	private func separation(_ left: Int, _ right: Int) -> Double {
		let gap = { (vertex: Int) in
			self.vertices[vertex].isDummy ? HomerGraphLayout.edgeSeparation : HomerGraphLayout.nodeSeparation
		}
		return (vertices[left].width + vertices[right].width) / 2 + (gap(left) + gap(right)) / 2
	}

	/// Brandes–Köpf, as dagre's `position/bk.js` does it: four alignments — each vertex lined up
	/// under the median of its neighbours above or below, scanning the layers from the left or
	/// the right — each compacted as tightly as the separations allow, shifted onto the
	/// narrowest, and every vertex placed midway between its two middle positions.
	mutating func assignX() {
		let upper = up.map(Self.unique)
		let lower = down.map(Self.unique)
		let conflicts = innerSegmentConflicts(upper: upper)
		var alignments: [(xs: [Double], isRight: Bool)] = []
		for downward in [true, false] {
			for fromRight in [false, true] {
				var layering = downward ? layers : layers.reversed()
				if fromRight {
					layering = layering.map { $0.reversed() }
				}
				let (root, _) = verticalAlignment(layering, neighbors: downward ? upper : lower, conflicts: conflicts)
				var xs = horizontalCompaction(layering, root: root)
				if fromRight {
					xs = xs.map { -$0 }
				}
				alignments.append((xs, fromRight))
			}
		}

		let narrowest = alignments.min { width(of: $0.xs) < width(of: $1.xs) }!.xs
		let target = (min: narrowest.min() ?? 0, max: narrowest.max() ?? 0)
		for index in alignments.indices {
			let xs = alignments[index].xs
			let delta = alignments[index].isRight ? target.max - (xs.max() ?? 0) : target.min - (xs.min() ?? 0)
			alignments[index].xs = xs.map { $0 + delta }
		}

		for vertex in vertices.indices {
			let positions = alignments.map { $0.xs[vertex] }.sorted()
			vertices[vertex].x = (positions[1] + positions[2]) / 2
		}
	}

	/// How wide the vertices are, placed at `xs`.
	private func width(of xs: [Double]) -> Double {
		var low = Double.infinity
		var high = -Double.infinity
		for (vertex, x) in xs.enumerated() {
			low = min(low, x - vertices[vertex].width / 2)
			high = max(high, x + vertices[vertex].width / 2)
		}
		return high - low
	}

	private static func unique(_ vertices: [Int]) -> [Int] {
		var seen = Set<Int>()
		return vertices.filter { seen.insert($0).inserted }
	}

	private struct Segment: Hashable {
		var a: Int
		var b: Int

		init(_ a: Int, _ b: Int) {
			self.a = min(a, b)
			self.b = max(a, b)
		}
	}

	/// Segments that cross a segment between two dummies (type 1 conflicts): the alignment never
	/// lines those up, so long edges keep running straight.
	private func innerSegmentConflicts(upper: [[Int]]) -> Set<Segment> {
		var conflicts = Set<Segment>()
		for rank in layers.indices.dropFirst() {
			let previousCount = layers[rank - 1].count
			let layer = layers[rank]
			var k0 = 0
			var scanPosition = 0
			for (index, vertex) in layer.enumerated() {
				let inner = vertices[vertex].isDummy ? upper[vertex].first { vertices[$0].isDummy } : nil
				let k1 = inner.map { order[$0] } ?? previousCount
				guard inner != nil || index == layer.count - 1 else {
					continue
				}
				for scanned in layer[scanPosition ... index] {
					for neighbor in upper[scanned] {
						let position = order[neighbor]
						if position < k0 || k1 < position, !(vertices[neighbor].isDummy && vertices[scanned].isDummy) {
							conflicts.insert(Segment(neighbor, scanned))
						}
					}
				}
				scanPosition = index + 1
				k0 = k1
			}
		}
		return conflicts
	}

	/// Each vertex joins the block of its median neighbour in the layer before, unless an
	/// earlier vertex of its layer took a neighbour further along or the segment conflicts.
	private func verticalAlignment(
		_ layering: [[Int]],
		neighbors: [[Int]],
		conflicts: Set<Segment>
	) -> (root: [Int], align: [Int]) {
		var root = Array(vertices.indices)
		var align = Array(vertices.indices)
		var position = Array(repeating: 0, count: vertices.count)
		for layer in layering {
			for (index, vertex) in layer.enumerated() {
				position[vertex] = index
			}
		}
		for layer in layering {
			var previousIndex = -1
			for vertex in layer {
				let candidates = neighbors[vertex].sorted { position[$0] < position[$1] }
				guard !candidates.isEmpty else {
					continue
				}
				let middle = Double(candidates.count - 1) / 2
				for index in Int(middle.rounded(.down)) ... Int(middle.rounded(.up)) {
					let neighbor = candidates[index]
					if align[vertex] == vertex, previousIndex < position[neighbor],
					   !conflicts.contains(Segment(vertex, neighbor))
					{
						align[neighbor] = vertex
						root[vertex] = root[neighbor]
						align[vertex] = root[vertex]
						previousIndex = position[neighbor]
					}
				}
			}
		}
		return (root, align)
	}

	/// Places the blocks as far left as their separations allow, then moves each right as far as
	/// the blocks after it allow, closing the gaps the first pass left.
	private func horizontalCompaction(_ layering: [[Int]], root: [Int]) -> [Double] {
		// The block graph: an edge from each block to the next one in some layer, as long as the
		// widest separation between their vertices there.
		var separations: [Segment: Double] = [:]
		var successors: [Int: [Int]] = [:]
		var predecessors: [Int: [Int]] = [:]
		var blocks = Set<Int>()
		for layer in layering {
			for (index, vertex) in layer.enumerated() {
				blocks.insert(root[vertex])
				guard index > 0 else {
					continue
				}
				let left = root[layer[index - 1]]
				let right = root[vertex]
				let key = Segment(left, right)
				let distance = separation(layer[index - 1], vertex)
				if let existing = separations[key] {
					separations[key] = max(existing, distance)
				}
				else {
					separations[key] = distance
					successors[left, default: []].append(right)
					predecessors[right, default: []].append(left)
				}
			}
		}

		var remaining = Dictionary(uniqueKeysWithValues: blocks.map { ($0, predecessors[$0]?.count ?? 0) })
		var sorted = blocks.filter { remaining[$0] == 0 }.sorted()
		var head = 0
		while head < sorted.count {
			for next in successors[sorted[head]] ?? [] {
				remaining[next]! -= 1
				if remaining[next] == 0 {
					sorted.append(next)
				}
			}
			head += 1
		}

		var blockX: [Int: Double] = [:]
		for block in sorted {
			blockX[block] = (predecessors[block] ?? []).map { blockX[$0]! + separations[Segment($0, block)]! }.max() ?? 0
		}
		for block in sorted.reversed() {
			if let limit = (successors[block] ?? []).map({ blockX[$0]! - separations[Segment(block, $0)]! }).min() {
				blockX[block] = max(blockX[block]!, limit)
			}
		}
		return vertices.indices.map { blockX[root[$0]] ?? 0 }
	}

	/// Ranks are as high as their highest vertex, half `ranksep` apart — two ranks per edge.
	mutating func assignY() {
		var cursor = HomerGraphLayout.margin
		for layer in layers {
			let height = layer.map { vertices[$0].height }.max() ?? 0
			for vertex in layer {
				vertices[vertex].y = cursor + height / 2
			}
			cursor += height + HomerGraphLayout.rankSeparation / 2
		}
	}

	// MARK: Output

	/// Where a node is drawn: its own size at the left of its box, which may be wider for loops.
	private func drawnRect(_ vertex: Int, shift: Double) -> CGRect {
		let box = vertices[vertex]
		let size = drawnSizes[vertex]
		return CGRect(
			x: box.x - box.width / 2 + shift,
			y: box.y - size.height / 2,
			width: size.width,
			height: size.height
		)
	}

	func output() -> HomerGraphLayout {
		let left = vertices.map { $0.x - $0.width / 2 }.min() ?? 0
		let shift = HomerGraphLayout.margin - left

		var nodes: [HomerGraphLayout.Node] = []
		for (vertex, id) in ids.enumerated() {
			let label = HomerGraphLayout.nodeLabel(id)
			nodes.append(.init(
				id: id,
				label: label.label,
				isTerminal: label.isTerminal,
				frame: drawnRect(vertex, shift: shift)
			))
		}

		var laidOut: [HomerGraphLayout.Edge] = []
		for edge in edges {
			let centers = edge.chain.map { CGPoint(x: vertices[$0].x + shift, y: vertices[$0].y) }
			var points = [Self.clip(drawnRect(edge.from, shift: shift), toward: centers.first!)]
			points += centers
			points.append(Self.clip(drawnRect(edge.to, shift: shift), toward: centers.last!))
			if edge.isReversed {
				points.reverse()
			}
			let labelFrame = edge.labelDummy.map { dummy in
				let size = edge.labelSize ?? .zero
				return CGRect(
					x: vertices[dummy].x + shift - size.width / 2,
					y: vertices[dummy].y - size.height / 2,
					width: size.width,
					height: size.height
				)
			}
			laidOut.append(.init(
				id: edge.id,
				source: ids[edge.isReversed ? edge.to : edge.from],
				target: ids[edge.isReversed ? edge.from : edge.to],
				label: edge.label,
				isConditional: edge.isConditional,
				isSelfLoop: false,
				points: points,
				labelFrame: labelFrame
			))
		}

		for (vertex, nodeLoops) in loops {
			let rect = drawnRect(vertex, shift: shift)
			let right = rect.maxX
			let middle = rect.midY
			let spread = HomerGraphLayout.loopSpread
			let labelLeft = right + Self.outerReach(loopCount: nodeLoops.count) + 2
			let labeledCount = nodeLoops.count { $0.label != nil }
			let pitch = Self.loopLabelPitch(nodeLoops)
			var row = 0
			for (index, loop) in nodeLoops.enumerated() {
				let reach = HomerGraphLayout.loopReach + Double(index) * HomerGraphLayout.loopStep
				var labelFrame: CGRect?
				if loop.label != nil {
					let labelY = middle + (Double(row) - Double(labeledCount - 1) / 2) * pitch
					row += 1
					labelFrame = CGRect(
						x: labelLeft,
						y: labelY - loop.labelSize.height / 2,
						width: loop.labelSize.width,
						height: loop.labelSize.height
					)
				}
				laidOut.append(.init(
					id: loop.id,
					source: ids[vertex],
					target: ids[vertex],
					label: loop.label,
					isConditional: loop.isConditional,
					isSelfLoop: true,
					points: [
						CGPoint(x: right, y: middle - spread),
						CGPoint(x: right + reach, y: middle - 2 * spread),
						CGPoint(x: right + reach, y: middle + 2 * spread),
						CGPoint(x: right, y: middle + spread),
					],
					labelFrame: labelFrame
				))
			}
		}
		laidOut.sort { $0.id < $1.id }

		var maxX = 0.0
		var maxY = 0.0
		for frame in nodes.map(\.frame) + laidOut.compactMap(\.labelFrame) {
			maxX = max(maxX, frame.maxX)
			maxY = max(maxY, frame.maxY)
		}
		for point in laidOut.flatMap(\.points) {
			maxX = max(maxX, point.x)
			maxY = max(maxY, point.y)
		}
		return HomerGraphLayout(
			size: CGSize(width: maxX + HomerGraphLayout.margin, height: maxY + HomerGraphLayout.margin),
			nodes: nodes,
			edges: laidOut
		)
	}

	/// Where the segment from `rect`'s centre toward `point` leaves the rect (dagre's
	/// `intersectRect`).
	static func clip(_ rect: CGRect, toward point: CGPoint) -> CGPoint {
		let dx = point.x - rect.midX
		let dy = point.y - rect.midY
		guard dx != 0 || dy != 0 else {
			return CGPoint(x: rect.midX, y: rect.midY)
		}
		var halfWidth = rect.width / 2
		var halfHeight = rect.height / 2
		if abs(dy) * halfWidth > abs(dx) * halfHeight {
			if dy < 0 {
				halfHeight = -halfHeight
			}
			return CGPoint(x: rect.midX + halfHeight * dx / dy, y: rect.midY + halfHeight)
		}
		if dx < 0 {
			halfWidth = -halfWidth
		}
		return CGPoint(x: rect.midX + halfWidth, y: rect.midY + halfWidth * dy / dx)
	}
}
