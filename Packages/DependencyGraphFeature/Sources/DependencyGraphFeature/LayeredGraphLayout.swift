import CoreGraphics
import Foundation

/// Node frames for a dependency graph, in graph points (the canvas scales them by its zoom).
public struct GraphLayout: Equatable, Sendable {
	public var frames: [String: CGRect]
	public var size: CGSize
	/// The horizontal bands the nodes sit in, top to bottom: one per layer, then the other
	/// platforms' modules, then modules with no edge in view. The canvas stripes them.
	public var bands: [Band]

	public struct Band: Equatable, Sendable {
		public var title: String
		public var minY: CGFloat
		public var maxY: CGFloat
	}

	public static let empty = GraphLayout(frames: [:], size: .zero, bands: [])
}

/// A layered (Sugiyama-style) layout: dependents above their dependencies.
///
/// 1. Layers by longest path: a module with no dependencies sits in the bottom layer, any other
///    one layer above its highest dependency, so every edge points down. A cycle (possible
///    through test dependencies) is broken where the walk meets it.
/// 2. Shorter edges: each module moves, within the room its edges leave, toward the side it has
///    more essential edges on (`minimizingSpans`). A module used by more than it uses rises
///    toward its users instead of sinking to the bottom with every other leaf.
/// 3. The other platforms' modules and the modules with no edge in view get bands of their own
///    below the layers, so they do not crowd the bottom layer.
/// 4. A band wider than `targetRowWidth` is spread over several rows, its nodes dealt to the
///    rows in turn so that x still grows with the order. Rows of one band hold no edges between
///    them, so edges still point down.
/// 5. Order within a band by repeated barycentre sweeps (the mean x of a node's neighbours over
///    the essential edges), which pulls connected modules together and uncrosses edges.
enum LayeredGraphLayout {
	struct Metrics: Equatable {
		var nodeHeight: CGFloat = 44
		var horizontalGap: CGFloat = 20
		var rowGap: CGFloat = 28
		var layerGap: CGFloat = 76
		var padding: CGFloat = 40
		/// Room at the left of each band for its label.
		var bandLabelWidth: CGFloat = 90
		var sweeps = 8
	}

	/// The node width for a title and subtitle, estimated from their length at the canvas's fonts
	/// (12 pt semibold, 9.5 pt regular) so the layout needs no text measuring.
	static func nodeWidth(title: String, subtitle: String) -> CGFloat {
		let textWidth = max(CGFloat(title.count) * 7.3, CGFloat(subtitle.count) * 5.7)
		return min(max(textWidth + 28, 110), 380)
	}

	/// `ids` in a stable order (it seeds the ordering), `dependencies` by id. Layer constraints
	/// come from all `dependencies`; edge lengths and ordering from `essentialDependencies`
	/// (the edges no longer path implies; all of them when nil).
	static func layout(
		ids: [String],
		widths: [String: CGFloat],
		dependencies: [String: [String]],
		essentialDependencies: [String: [String]]? = nil,
		boundaryIDs: Set<String> = [],
		metrics: Metrics = Metrics()
	) -> GraphLayout {
		guard !ids.isEmpty else {
			return .empty
		}

		let idSet = Set(ids)
		let dependencies = dependencies.mapValues { $0.filter(idSet.contains) }
		let essential = (essentialDependencies ?? dependencies).mapValues { $0.filter(idSet.contains) }
		let dependents = inverted(dependencies, keys: idSet)
		let essentialDependents = inverted(essential, keys: idSet)

		let boundary = ids.filter(boundaryIDs.contains)
		let unconnected = ids.filter { id in
			!boundaryIDs.contains(id) && (dependencies[id] ?? []).isEmpty && (dependents[id] ?? []).isEmpty
		}
		let excluded = Set(boundary).union(unconnected)
		let layered = ids.filter { !excluded.contains($0) }
		let layeredSet = Set(layered)
		let layeredDependencies = dependencies.mapValues { $0.filter(layeredSet.contains) }

		var layerOf = layers(ids: layered, dependencies: layeredDependencies)
		layerOf = minimizingSpans(
			layerOf,
			dependencies: layeredDependencies,
			essentialDependencies: essential.mapValues { $0.filter(layeredSet.contains) }
		)

		// Top to bottom; empty layers (left by the moves) dropped.
		let used = Set(layerOf.values).sorted(by: >)
		var bands: [(title: String, ids: [String])] = used.enumerated().map { index, layer in
			("Layer \(used.count - index)", layered.filter { layerOf[$0] == layer })
		}
		if !boundary.isEmpty {
			bands.append(("Other platforms", boundary))
		}
		if !unconnected.isEmpty {
			bands.append(("Unconnected", unconnected))
		}

		func width(_ id: String) -> CGFloat {
			widths[id] ?? 120
		}

		let totalWidth = ids.reduce(0) { $0 + width($1) + metrics.horizontalGap }
		let targetRowWidth = max(1400, (totalWidth * (metrics.nodeHeight + metrics.rowGap)).squareRoot() * 1.5)

		// Centre x of every node given each band's order; rows centred on x = 0.
		var centerX: [String: CGFloat] = [:]
		func rows(of band: [String]) -> [[String]] {
			let bandWidth = band.reduce(0) { $0 + width($1) + metrics.horizontalGap }
			let rowCount = max(1, Int((bandWidth / targetRowWidth).rounded(.up)))
			var rows: [[String]] = Array(repeating: [], count: rowCount)
			for (index, id) in band.enumerated() {
				rows[index % rowCount].append(id)
			}
			return rows
		}
		func place(_ band: [String]) {
			for row in rows(of: band) {
				let rowWidth = row.reduce(0) { $0 + width($1) } + metrics.horizontalGap * CGFloat(max(0, row.count - 1))
				var x = -rowWidth / 2
				for id in row {
					centerX[id] = x + width(id) / 2
					x += width(id) + metrics.horizontalGap
				}
			}
		}
		bands.map(\.ids).forEach(place)

		for sweep in 0 ..< metrics.sweeps {
			// Alternate downward and upward passes, each settling a band against its neighbours'
			// current positions.
			let order = sweep.isMultiple(of: 2) ? Array(bands.indices) : bands.indices.reversed()
			for bandIndex in order {
				let keyed = bands[bandIndex].ids.enumerated().map { offset, id -> (id: String, key: CGFloat, offset: Int) in
					let neighbours = (essential[id] ?? []) + (essentialDependents[id] ?? [])
					let positions = neighbours.compactMap { centerX[$0] }
					let key = positions.isEmpty
						? centerX[id, default: 0]
						: positions.reduce(0, +) / CGFloat(positions.count)
					return (id, key, offset)
				}
				bands[bandIndex].ids = keyed
					.sorted { ($0.key, $0.offset) < ($1.key, $1.offset) }
					.map(\.id)
				place(bands[bandIndex].ids)
			}
		}

		// Final frames: rows top to bottom, shifted so the leftmost node starts after the
		// padding and the band labels.
		let minX = ids.compactMap { id in centerX[id].map { $0 - width(id) / 2 } }.min() ?? 0
		let maxX = ids.compactMap { id in centerX[id].map { $0 + width(id) / 2 } }.max() ?? 0
		let left = metrics.padding + metrics.bandLabelWidth
		var frames: [String: CGRect] = [:]
		var bandFrames: [GraphLayout.Band] = []
		var y = metrics.padding
		for (bandIndex, band) in bands.enumerated() {
			// Half of the gap above and below each band belongs to it, so stripes meet.
			let top = bandIndex == 0 ? 0 : y - metrics.layerGap / 2
			for row in rows(of: band.ids) {
				for id in row {
					let x = centerX[id, default: 0] - width(id) / 2 - minX + left
					frames[id] = CGRect(x: x, y: y, width: width(id), height: metrics.nodeHeight)
				}
				y += metrics.nodeHeight + metrics.rowGap
			}
			y += metrics.layerGap - metrics.rowGap
			let isLast = bandIndex == bands.count - 1
			let bottom = isLast ? y - metrics.layerGap + metrics.padding : y - metrics.layerGap / 2
			bandFrames.append(GraphLayout.Band(title: band.title, minY: top, maxY: bottom))
		}

		return GraphLayout(
			frames: frames,
			size: CGSize(
				width: maxX - minX + left + metrics.padding,
				height: bandFrames.last?.maxY ?? 0
			),
			bands: bandFrames
		)
	}

	/// Longest-path layer of each node: 0 without dependencies, else one above the highest.
	static func layers(ids: [String], dependencies: [String: [String]]) -> [String: Int] {
		var layer: [String: Int] = [:]
		var visiting: Set<String> = []

		// Iterative depth-first walk, so a deep chain cannot overflow the stack.
		for root in ids where layer[root] == nil {
			var stack: [(id: String, expanded: Bool)] = [(root, false)]
			while let entry = stack.popLast() {
				let id = entry.id
				if entry.expanded {
					visiting.remove(id)
					let below = (dependencies[id] ?? []).compactMap { layer[$0] }
					layer[id] = (below.max() ?? -1) + 1
					continue
				}
				guard layer[id] == nil, !visiting.contains(id) else {
					continue
				}

				visiting.insert(id)
				stack.append((id, true))
				// A dependency already on the walk's path closes a cycle; skipping it breaks the
				// cycle there.
				for dependency in dependencies[id] ?? [] where layer[dependency] == nil && !visiting.contains(dependency) {
					stack.append((dependency, false))
				}
			}
		}
		return layer
	}

	/// Moves each module, within the room its downward edges leave (above its highest
	/// dependency, below its lowest dependent), toward the side with more essential edges: the
	/// total length of its essential edges falls with every move, so the loop settles. Only edges
	/// pointing down in `initial` constrain or count, so a cycle's upward edge is ignored.
	static func minimizingSpans(
		_ initial: [String: Int],
		dependencies: [String: [String]],
		essentialDependencies: [String: [String]]
	) -> [String: Int] {
		var layer = initial
		let top = initial.values.max() ?? 0
		func downward(_ adjacency: [String: [String]]) -> [String: [String]] {
			adjacency.reduce(into: [:]) { result, entry in
				let targets = entry.value.filter { (initial[entry.key] ?? 0) > (initial[$0] ?? 0) }
				if !targets.isEmpty {
					result[entry.key] = targets
				}
			}
		}
		let below = downward(dependencies)
		let above = inverted(below, keys: Set(initial.keys))
		let essentialBelow = downward(essentialDependencies)
		let essentialAbove = inverted(essentialBelow, keys: Set(initial.keys))

		let ids = initial.keys.sorted()
		for _ in 0 ..< 100 {
			var moved = false
			for id in ids {
				let down = essentialBelow[id]?.count ?? 0
				let up = essentialAbove[id]?.count ?? 0
				guard down != up else {
					continue
				}

				let lowest = ((below[id] ?? []).compactMap { layer[$0] }.max() ?? -1) + 1
				let highest = ((above[id] ?? []).compactMap { layer[$0] }.min() ?? (top + 1)) - 1
				let target = up > down ? highest : lowest
				if target != layer[id] {
					layer[id] = target
					moved = true
				}
			}
			if !moved {
				break
			}
		}
		return layer
	}

	private static func inverted(_ adjacency: [String: [String]], keys: Set<String>) -> [String: [String]] {
		var result: [String: [String]] = [:]
		for (from, targets) in adjacency where keys.contains(from) {
			for target in targets {
				result[target, default: []].append(from)
			}
		}
		return result
	}
}
