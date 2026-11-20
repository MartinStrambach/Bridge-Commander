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
