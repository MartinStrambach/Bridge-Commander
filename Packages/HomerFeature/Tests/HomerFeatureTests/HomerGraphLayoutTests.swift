import CoreGraphics
import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer workflow graph layout")
struct HomerGraphLayoutTests {
	private typealias Topology = HomerLangGraphStatus.Topology
	private typealias Edge = HomerLangGraphStatus.Topology.Edge

	private static let nodeSize = CGSize(width: 100, height: 36)

	private static func topology(_ nodes: [String], _ edges: [Edge]) -> Topology {
		Topology(nodes: nodes.map(Topology.Node.init(id:)), edges: edges)
	}

	private static func layout(
		_ topology: Topology,
		labelSize: CGSize = CGSize(width: 60, height: 16)
	) throws -> HomerGraphLayout {
		let nodeSizes = Dictionary(topology.nodes.map { ($0.id, nodeSize) }, uniquingKeysWith: { first, _ in first })
		let labelSizes = Dictionary(
			topology.edges.compactMap(HomerGraphLayout.edgeLabel).map { ($0, labelSize) },
			uniquingKeysWith: { first, _ in first }
		)
		return try #require(HomerGraphLayout.make(topology: topology, nodeSizes: nodeSizes, labelSizes: labelSizes))
	}

	private static func frame(_ id: String, in layout: HomerGraphLayout) throws -> CGRect {
		try #require(layout.nodes.first { $0.id == id }).frame
	}

	/// Whether a point lies on a rect's border, give or take rounding.
	private static func isOnBorder(_ point: CGPoint, of rect: CGRect) -> Bool {
		let tolerance = 0.01
		let inside = rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
		let onEdge = abs(point.x - rect.minX) < tolerance || abs(point.x - rect.maxX) < tolerance
			|| abs(point.y - rect.minY) < tolerance || abs(point.y - rect.maxY) < tolerance
		return inside && onEdge
	}

	/// The factory agent's workflow (`factory_graph/graph.py`): a chain with a skip to
	/// `finalize` from almost every node, a self-loop and the fix rounds' cycles.
	private static let factory: Topology = {
		var edges: [Edge] = [.init(source: "__start__", target: "entry"), .init(source: "entry", target: "gate")]
		func routes(_ source: String, _ targets: [String]) {
			edges += targets.map { Edge(source: source, target: $0, conditional: true) }
		}
		routes("gate", ["readiness", "finalize"])
		routes("readiness", ["triage", "finalize"])
		routes("triage", ["inspection", "impl_target", "finalize"])
		routes("inspection", ["impl_target", "finalize"])
		routes("impl_target", ["scoping", "finalize"])
		routes("scoping", ["approval", "finalize"])
		routes("approval", ["dev", "finalize"])
		routes("dev", ["dev", "mac_verification", "android_tests", "testlink", "finalize"])
		routes("mac_verification", ["verdict", "fix", "testlink", "finalize"])
		edges.append(.init(source: "android_tests", target: "verdict"))
		routes("verdict", ["verification", "fix", "testlink", "finalize"])
		routes("verification", ["fix", "testlink", "finalize"])
		routes("fix", ["mac_verification", "android_tests", "testlink", "finalize"])
		edges += [.init(source: "testlink", target: "finalize"), .init(source: "finalize", target: "__end__")]
		return topology(
			[
				"__start__", "entry", "gate", "readiness", "triage", "inspection", "impl_target", "scoping", "approval",
				"dev", "mac_verification", "verification", "android_tests", "verdict", "fix", "testlink", "finalize",
				"__end__",
			],
			edges
		)
	}()

	@Test("a topology's edges decode, with no label or conditional flag meaning a fixed edge")
	func decodesEdges() throws {
		let json = """
			{ "nodes": [{ "id": "__start__" }, { "id": "plan" }, { "id": "__end__" }],
			  "edges": [
			    { "source": "__start__", "target": "plan" },
			    { "source": "plan", "target": "__end__", "label": "done", "conditional": true }
			  ] }
			"""

		let topology = try JSONDecoder().decode(Topology.self, from: Data(json.utf8))

		#expect(topology.edges == [
			Edge(source: "__start__", target: "plan"),
			Edge(source: "plan", target: "__end__", label: "done", conditional: true),
		])
	}

	@Test("a chain runs straight down, its edges from the bottom of one box to the top of the next")
	func chain() throws {
		let layout = try Self.layout(Self.topology(
			["__start__", "plan", "__end__"],
			[.init(source: "__start__", target: "plan"), .init(source: "plan", target: "__end__")]
		))

		let start = try Self.frame("__start__", in: layout)
		let plan = try Self.frame("plan", in: layout)
		let end = try Self.frame("__end__", in: layout)
		#expect(start.maxY < plan.minY)
		#expect(plan.maxY < end.minY)
		#expect(start.midX == plan.midX)
		#expect(plan.midX == end.midX)
		// Ranks are `ranksep` apart: two half-separations around the empty label rank.
		#expect(Double(plan.minY - start.maxY) == HomerGraphLayout.rankSeparation)

		let edge = try #require(layout.edges.first { $0.source == "plan" })
		#expect(edge.points.first == CGPoint(x: plan.midX, y: plan.maxY))
		#expect(edge.points.last == CGPoint(x: end.midX, y: end.minY))
		#expect(layout.nodes.map(\.label) == ["start", "plan", "end"])
		#expect(layout.nodes.map(\.isTerminal) == [true, false, true])
	}

	@Test("the factory workflow: no boxes overlap, and every edge runs from its source's border to its target's")
	func factoryWorkflow() throws {
		let layout = try Self.layout(Self.factory)

		#expect(layout.nodes.count == 18)
		#expect(layout.edges.map(\.id) == Array(Self.factory.edges.indices))
		for (index, node) in layout.nodes.enumerated() {
			#expect(node.frame.minX >= 0 && node.frame.maxX <= layout.size.width)
			#expect(node.frame.minY >= 0 && node.frame.maxY <= layout.size.height)
			for other in layout.nodes[(index + 1)...] {
				#expect(!node.frame.intersects(other.frame), "\(node.id) overlaps \(other.id)")
			}
		}
		for edge in layout.edges where !edge.isSelfLoop {
			let first = try #require(edge.points.first)
			let last = try #require(edge.points.last)
			#expect(Self.isOnBorder(first, of: try Self.frame(edge.source, in: layout)), "\(edge.source) → \(edge.target)")
			#expect(Self.isOnBorder(last, of: try Self.frame(edge.target, in: layout)), "\(edge.source) → \(edge.target)")
		}
		// The workflow reads top to bottom: start first, end last.
		#expect(try Double(Self.frame("__start__", in: layout).minY) == HomerGraphLayout.margin)
		let end = try Self.frame("__end__", in: layout)
		#expect(layout.nodes.allSatisfy { $0.frame.minY <= end.minY })
		for (source, target) in [("__start__", "entry"), ("entry", "gate"), ("gate", "readiness"), ("finalize", "__end__")] {
			#expect(try Self.frame(source, in: layout).maxY < Self.frame(target, in: layout).minY)
		}
	}

	@Test("an edge back up a cycle still starts at its source and ends at its target")
	func backEdge() throws {
		let layout = try Self.layout(Self.topology(
			["review", "fix"],
			[.init(source: "review", target: "fix"), .init(source: "fix", target: "review", conditional: true)]
		))

		let review = try Self.frame("review", in: layout)
		let fix = try Self.frame("fix", in: layout)
		#expect(review.maxY < fix.minY)
		let back = try #require(layout.edges.first { $0.source == "fix" })
		#expect(back.isConditional)
		#expect(Self.isOnBorder(try #require(back.points.first), of: fix))
		#expect(Self.isOnBorder(try #require(back.points.last), of: review))
	}

	@Test("a self-loop is drawn on the node's right; the node keeps its size and the layout makes room")
	func selfLoop() throws {
		let layout = try Self.layout(Self.topology(
			["dev"],
			[.init(source: "dev", target: "dev", label: "next slice", conditional: true)]
		))

		let dev = try Self.frame("dev", in: layout)
		#expect(dev.size == Self.nodeSize)
		let loop = try #require(layout.edges.first)
		#expect(loop.isSelfLoop)
		#expect(loop.points.count == 4)
		#expect(loop.points.first?.x == dev.maxX)
		#expect(loop.points.last?.x == dev.maxX)
		let label = try #require(loop.labelFrame)
		#expect(label.minX > dev.maxX)
		#expect(layout.size.width >= label.maxX)
	}

	@Test("a label sits on its edge, in the rank between the two nodes, at the size measured for it")
	func edgeLabel() throws {
		let size = CGSize(width: 80, height: 16)
		let layout = try Self.layout(
			Self.topology(["route", "done"], [.init(source: "route", target: "done", label: "finished", conditional: true)]),
			labelSize: size
		)

		let route = try Self.frame("route", in: layout)
		let done = try Self.frame("done", in: layout)
		let edge = try #require(layout.edges.first)
		let label = try #require(edge.labelFrame)
		#expect(edge.label == "finished")
		#expect(label.size == size)
		#expect(label.minY > route.maxY)
		#expect(label.maxY < done.minY)
		#expect(edge.points.contains(CGPoint(x: label.midX, y: label.midY)))
	}

	@Test("an edge to a node the topology does not list is left out, and a repeated node drawn once")
	func strayEdgesAndDuplicates() throws {
		let layout = try Self.layout(Self.topology(
			["a", "b", "a"],
			[.init(source: "a", target: "b"), .init(source: "b", target: "ghost")]
		))

		#expect(layout.nodes.map(\.id) == ["a", "b"])
		#expect(layout.edges.map(\.id) == [0])
	}

	@Test("above the console's render cap there is no layout")
	func renderCap() {
		let nodes = (0 ... HomerGraphLayout.maxNodes).map { "n\($0)" }
		#expect(HomerGraphLayout.make(topology: Self.topology(nodes, []), nodeSizes: [:], labelSizes: [:]) == nil)

		let edges = (0 ... HomerGraphLayout.maxEdges).map { _ in Edge(source: "a", target: "b") }
		#expect(HomerGraphLayout.make(topology: Self.topology(["a", "b"], edges), nodeSizes: [:], labelSizes: [:]) == nil)
	}

	@Test("long names and labels are cut to 40 characters; start and end are named so")
	func labels() {
		let long = String(repeating: "x", count: 41)
		#expect(HomerGraphLayout.truncatedLabel(long) == String(repeating: "x", count: 39) + "…")
		#expect(HomerGraphLayout.truncatedLabel(String(repeating: "x", count: 40)).count == 40)
		#expect(HomerGraphLayout.nodeLabel("__start__") == ("start", true))
		#expect(HomerGraphLayout.nodeLabel("__end__") == ("end", true))
		#expect(HomerGraphLayout.nodeLabel("plan") == ("plan", false))
		#expect(HomerGraphLayout.edgeLabel(Edge(source: "a", target: "b", label: "")) == nil)
	}

	@Test("command dots are centred along the box, squeezed when many, and the oldest dropped past that")
	func commandDots() {
		let three = HomerWorkflowCommandDotRow.dots(["ok", "ok", "running"], width: 100)
		#expect(three.map(\.x) == [43, 50, 57])
		#expect(three.map(\.state) == ["ok", "ok", "running"])

		// 72 wide leaves 64: 12 dots fit at 5.5 apart, so the 4 oldest of 16 go.
		let many = HomerWorkflowCommandDotRow.dots((0 ..< 16).map { "s\($0)" }, width: 72)
		#expect(many.count == 12)
		#expect(many.first?.state == "s4")
		#expect(many.last?.state == "s15")
		#expect(many.allSatisfy { $0.x >= 4 && $0.x <= 68 })

		#expect(HomerWorkflowCommandDotRow.dots([], width: 72).isEmpty)
	}
}
