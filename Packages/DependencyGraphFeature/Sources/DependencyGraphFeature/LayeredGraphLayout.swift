import CoreGraphics
import Foundation

/// Node frames for a dependency graph, in graph points (the canvas scales them by its zoom).
public struct GraphLayout: Equatable, Sendable {
	public var frames: [String: CGRect]
	public var size: CGSize

	public static let empty = GraphLayout(frames: [:], size: .zero)
}

/// A layered (Sugiyama-style) layout: dependents above their dependencies.
///
/// 1. Layers by longest path: a module with no dependencies sits in the bottom layer, any other
///    one layer above its highest dependency, so every edge points down. A cycle (possible
///    through test dependencies) is broken where the walk meets it.
/// 2. A layer wider than `targetRowWidth` is spread over several rows, its nodes dealt to the
///    rows in turn so that x still grows with the order. Rows of one layer hold no edges between
///    them, so edges still point down.
/// 3. Order within a layer by repeated barycentre sweeps (the mean x of a node's neighbours),
///    which pulls connected modules together and uncrosses edges.
enum LayeredGraphLayout {
	struct Metrics: Equatable {
		var nodeHeight: CGFloat = 44
		var horizontalGap: CGFloat = 20
		var rowGap: CGFloat = 36
		var layerGap: CGFloat = 84
		var padding: CGFloat = 40
		var sweeps = 8
	}

	/// The node width for a title and subtitle, estimated from their length at the canvas's fonts
	/// (12 pt semibold, 9.5 pt regular) so the layout needs no text measuring.
	static func nodeWidth(title: String, subtitle: String) -> CGFloat {
		let textWidth = max(CGFloat(title.count) * 7.3, CGFloat(subtitle.count) * 5.7)
		return min(max(textWidth + 28, 110), 380)
	}

	/// `ids` in a stable order (it seeds the ordering), `dependencies` by id.
	static func layout(
		ids: [String],
		widths: [String: CGFloat],
		dependencies: [String: [String]],
		metrics: Metrics = Metrics()
	) -> GraphLayout {
		guard !ids.isEmpty else {
			return .empty
		}

		let idSet = Set(ids)
		let dependencies = dependencies.mapValues { $0.filter(idSet.contains) }
		var dependents: [String: [String]] = [:]
		for (from, targets) in dependencies where idSet.contains(from) {
			for target in targets {
				dependents[target, default: []].append(from)
			}
		}

		let layerOf = layers(ids: ids, dependencies: dependencies)
		let layerCount = (layerOf.values.max() ?? 0) + 1
		// Index 0 is the top layer.
		var layers: [[String]] = Array(repeating: [], count: layerCount)
		for id in ids {
			layers[layerCount - 1 - layerOf[id, default: 0]].append(id)
		}

		func width(_ id: String) -> CGFloat {
			widths[id] ?? 120
		}

		let totalWidth = ids.reduce(0) { $0 + width($1) + metrics.horizontalGap }
		let targetRowWidth = max(1400, (totalWidth * (metrics.nodeHeight + metrics.rowGap)).squareRoot() * 1.5)

		// Centre x of every node given each layer's order; rows centred on x = 0.
		var centerX: [String: CGFloat] = [:]
		func rows(of layer: [String]) -> [[String]] {
			let layerWidth = layer.reduce(0) { $0 + width($1) + metrics.horizontalGap }
			let rowCount = max(1, Int((layerWidth / targetRowWidth).rounded(.up)))
			var rows: [[String]] = Array(repeating: [], count: rowCount)
			for (index, id) in layer.enumerated() {
				rows[index % rowCount].append(id)
			}
			return rows
		}
		func place(_ layer: [String]) {
			for row in rows(of: layer) {
				let rowWidth = row.reduce(0) { $0 + width($1) } + metrics.horizontalGap * CGFloat(max(0, row.count - 1))
				var x = -rowWidth / 2
				for id in row {
					centerX[id] = x + width(id) / 2
					x += width(id) + metrics.horizontalGap
				}
			}
		}
		layers.forEach(place)

		for sweep in 0 ..< metrics.sweeps {
			// Alternate downward and upward passes, each settling a layer against its neighbours'
			// current positions.
			let order = sweep.isMultiple(of: 2) ? Array(layers.indices) : layers.indices.reversed()
			for layerIndex in order {
				let keyed = layers[layerIndex].enumerated().map { offset, id -> (id: String, key: CGFloat, offset: Int) in
					let neighbours = (dependencies[id] ?? []) + (dependents[id] ?? [])
					let positions = neighbours.compactMap { centerX[$0] }
					let key = positions.isEmpty
						? centerX[id, default: 0]
						: positions.reduce(0, +) / CGFloat(positions.count)
					return (id, key, offset)
				}
				layers[layerIndex] = keyed
					.sorted { ($0.key, $0.offset) < ($1.key, $1.offset) }
					.map(\.id)
				place(layers[layerIndex])
			}
		}

		// Final frames: rows top to bottom, shifted so the leftmost node starts at the padding.
		let minX = ids.compactMap { id in centerX[id].map { $0 - width(id) / 2 } }.min() ?? 0
		let maxX = ids.compactMap { id in centerX[id].map { $0 + width(id) / 2 } }.max() ?? 0
		var frames: [String: CGRect] = [:]
		var y = metrics.padding
		for (layerIndex, layer) in layers.enumerated() {
			if layerIndex > 0 {
				y += metrics.layerGap - metrics.rowGap
			}
			for row in rows(of: layer) {
				for id in row {
					let x = centerX[id, default: 0] - width(id) / 2 - minX + metrics.padding
					frames[id] = CGRect(x: x, y: y, width: width(id), height: metrics.nodeHeight)
				}
				y += metrics.nodeHeight + metrics.rowGap
			}
		}

		return GraphLayout(
			frames: frames,
			size: CGSize(
				width: maxX - minX + metrics.padding * 2,
				height: y - metrics.rowGap + metrics.padding
			)
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
}
