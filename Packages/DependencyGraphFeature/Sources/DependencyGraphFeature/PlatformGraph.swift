import Foundation

/// The part of a `DependencyGraph` one tab shows: the platform's modules, the edges between
/// them, and — when asked — the other platforms' modules they depend on directly, as boundary
/// nodes whose own dependencies are not followed.
public struct PlatformGraph: Equatable, Sendable {
	public var modules: [DependencyModule]
	public var boundaryModuleIDs: Set<String>
	public var edges: [DependencyEdge]
	/// Direct dependencies and dependents, by module id, over `edges`.
	public var dependencies: [String: [String]]
	public var dependents: [String: [String]]
	/// Edges another path already implies (a → c when a → b → … → c): left out of the drawing
	/// unless asked for, and of the layout's ordering. Leaving them out keeps every module's
	/// reach (a transitive reduction) and removes most of the long edges.
	public var indirectEdges: Set<DependencyEdge>

	public static let empty = PlatformGraph(modules: [], boundaryModuleIDs: [], edges: [])

	init(modules: [DependencyModule], boundaryModuleIDs: Set<String>, edges: [DependencyEdge]) {
		self.modules = modules
		self.boundaryModuleIDs = boundaryModuleIDs
		self.edges = edges
		var dependencies: [String: [String]] = [:]
		var dependents: [String: [String]] = [:]
		for edge in edges {
			dependencies[edge.from, default: []].append(edge.to)
			dependents[edge.to, default: []].append(edge.from)
		}
		self.dependencies = dependencies
		self.dependents = dependents
		self.indirectEdges = Self.indirectEdges(
			among: modules.map(\.id),
			edges: edges,
			dependencies: dependencies
		)
	}

	/// The transitive reduction's complement, over the edges that point down the longest-path
	/// layering. A cycle (only through test dependencies) keeps its upward edge; the reduction
	/// of a graph with cycles is not unique, and dropping both directions could cut a module off.
	static func indirectEdges(
		among ids: [String],
		edges: [DependencyEdge],
		dependencies: [String: [String]]
	) -> Set<DependencyEdge> {
		let layer = LayeredGraphLayout.layers(ids: ids, dependencies: dependencies)
		func pointsDown(_ from: String, _ to: String) -> Bool {
			(layer[from] ?? 0) > (layer[to] ?? 0)
		}

		// Everything below each module along downward edges, lowest layers first so each
		// module's dependencies are done before it.
		var below: [String: Set<String>] = [:]
		for id in ids.sorted(by: { (layer[$0] ?? 0) < (layer[$1] ?? 0) }) {
			var reach: Set<String> = []
			for dependency in dependencies[id] ?? [] where pointsDown(id, dependency) {
				reach.insert(dependency)
				reach.formUnion(below[dependency] ?? [])
			}
			below[id] = reach
		}

		return Set(edges.filter { edge in
			guard pointsDown(edge.from, edge.to) else {
				return false
			}
			return (dependencies[edge.from] ?? []).contains { other in
				other != edge.to && pointsDown(edge.from, other) && below[other]?.contains(edge.to) == true
			}
		})
	}

	public static func make(
		from graph: DependencyGraph,
		platform: ModulePlatform,
		includesOtherPlatforms: Bool,
		includesTestDependencies: Bool
	) -> PlatformGraph {
		let own = graph.modules.filter { $0.kind.platform == platform }
		let ownIDs = Set(own.map(\.id))
		let modulesByID = Dictionary(graph.modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

		var boundary: Set<String> = []
		let edges = graph.edges.filter { edge in
			guard ownIDs.contains(edge.from), includesTestDependencies || !edge.isTest else {
				return false
			}
			if ownIDs.contains(edge.to) {
				return true
			}
			guard includesOtherPlatforms, modulesByID[edge.to] != nil else {
				return false
			}
			boundary.insert(edge.to)
			return true
		}

		let boundaryModules = boundary.sorted().compactMap { modulesByID[$0] }
		return PlatformGraph(modules: own + boundaryModules, boundaryModuleIDs: boundary, edges: edges)
	}

	public func module(withID id: String) -> DependencyModule? {
		modules.first { $0.id == id }
	}

	/// Everything `id` depends on, directly or not.
	public func transitiveDependencies(of id: String) -> Set<String> {
		Self.reachable(from: id, along: dependencies)
	}

	/// Everything that depends on `id`, directly or not.
	public func transitiveDependents(of id: String) -> Set<String> {
		Self.reachable(from: id, along: dependents)
	}

	private static func reachable(from start: String, along adjacency: [String: [String]]) -> Set<String> {
		var visited: Set<String> = []
		var stack = adjacency[start] ?? []
		while let next = stack.popLast() {
			guard next != start, visited.insert(next).inserted else {
				continue
			}
			stack += adjacency[next] ?? []
		}
		return visited
	}
}
