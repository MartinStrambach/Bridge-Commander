import Foundation
import Testing
@testable import DiskUsageFeature

@Suite("Sunburst transition")
struct SunburstTransitionTests {
	/// root: a (500, a folder of a1 300 + a2 200), b 250, c 250.
	private let a1 = DiskNode(name: "a1", kind: .file, size: 300, itemCount: 1)
	private let a2 = DiskNode(name: "a2", kind: .file, size: 200, itemCount: 1)
	private var a: DiskNode { DiskNode(directoryNamed: "a", children: [a1, a2]) }
	private let b = DiskNode(name: "b", kind: .file, size: 250, itemCount: 1)
	private let c = DiskNode(name: "c", kind: .file, size: 250, itemCount: 1)

	private func tree() -> (root: DiskNode, a: DiskNode) {
		let a = a
		return (DiskNode(directoryNamed: "root", children: [a, b, c]), a)
	}

	private func member(_ transition: SunburstTransition, named name: String, leaving: Bool = false) -> SunburstTransition.Member? {
		transition.members.first { $0.segment.node?.name == name && $0.isLeaving == leaving }
	}

	@Test("opening a folder zooms into its arc: its contents move one ring in and spread over the circle")
	func zoomsIntoOpenedFolder() {
		let (root, a) = tree()
		let transition = SunburstTransition(from: SunburstLayout(center: root), to: SunburstLayout(center: a))
		#expect(transition.zoom == .into(start: 0, end: 0.5, depth: 1))

		// a1 was drawn under a, in the second ring over the first 60% of a's half; it stays and moves.
		let a1 = try! #require(member(transition, named: "a1"))
		#expect(a1.from == .init(start: 0, end: 0.3, depth: 2))
		#expect(a1.to == .init(start: 0, end: 0.6, depth: 1))
		#expect(a1.from.opacity == 1 && a1.to.opacity == 1)

		// The opened folder's own arc grows to the whole circle while sliding under the centre, fading.
		let opened = try! #require(member(transition, named: "a", leaving: true))
		#expect(opened.from == .init(start: 0, end: 0.5, depth: 1))
		#expect(opened.to == .init(start: 0, end: 1, depth: 0, opacity: 0))

		// Siblings collapse onto the top of the circle.
		let b = try! #require(member(transition, named: "b", leaving: true))
		#expect(b.to == .init(start: 1, end: 1, depth: 0, opacity: 0))
	}

	@Test("going up zooms out: the old centre's contents shrink into its arc, its siblings grow out of the seam")
	func zoomsOutToParent() {
		let (root, a) = tree()
		let transition = SunburstTransition(from: SunburstLayout(center: a), to: SunburstLayout(center: root))
		#expect(transition.zoom == .outOf(start: 0, end: 0.5, depth: 1))

		let a2 = try! #require(member(transition, named: "a2"))
		#expect(a2.from == .init(start: 0.6, end: 1, depth: 1))
		#expect(a2.to == .init(start: 0.3, end: 0.5, depth: 2))

		let c = try! #require(member(transition, named: "c"))
		#expect(c.from == .init(start: 1, end: 1, depth: 0, opacity: 0))
		#expect(c.to == .init(start: 0.75, end: 1, depth: 1))
	}

	@Test("a deletion keeps the rest where it is: the remaining arcs slide, the removed one fades in place")
	func deletionFadesInPlace() {
		let (root, _) = tree()
		let after = root.removingChild(named: "a")
		let transition = SunburstTransition(from: SunburstLayout(center: root), to: SunburstLayout(center: after))
		#expect(transition.zoom == .none)

		let b = try! #require(member(transition, named: "b"))
		#expect(b.from == .init(start: 0.5, end: 0.75, depth: 1))
		#expect(b.to == .init(start: 0, end: 0.5, depth: 1))

		let removed = try! #require(member(transition, named: "a", leaving: true))
		#expect(removed.to == .init(start: 0, end: 0.5, depth: 1, opacity: 0))
		// What goes is drawn first, so what stays paints over it.
		#expect(transition.members.prefix(while: \.isLeaving).count == transition.members.filter(\.isLeaving).count)
	}

	@Test("frames interpolate linearly and leave out what cannot be seen")
	func framesInterpolate() {
		let (root, a) = tree()
		let transition = SunburstTransition(from: SunburstLayout(center: root), to: SunburstLayout(center: a))
		// At the start only the old layout is drawn: what is still to come has no opacity yet.
		let start = transition.frames(at: 0)
		#expect(Set(start.map { $0.segment.node?.name }) == Set(SunburstLayout(center: root).segments.map { $0.node?.name }))
		#expect(start.allSatisfy(\.isLeaving) == false && start.contains(where: \.isLeaving))
		// Halfway, a1 is between its two frames.
		let halfway = try! #require(transition.frames(at: 0.5).first { $0.segment.node?.name == "a1" })
		#expect(abs(halfway.frame.end - 0.45) < 1e-9)
		#expect(halfway.frame.start == 0 && halfway.frame.depth == 1.5 && halfway.frame.opacity == 1)
		// At the end only the new layout is left, exactly where it lays its segments out.
		let end = transition.frames(at: 1)
		#expect(end.map(\.segment.id) == SunburstLayout(center: a).segments.map(\.id))
		#expect(end.allSatisfy { $0.frame == .init($0.segment) && !$0.isLeaving })
	}

	@Test("a folder too thin to be drawn is opened out of its parent's rest arc")
	func thinFolderZoomsOutOfRest() {
		var children = [DiskNode(name: "big", kind: .file, size: 1_000_000, itemCount: 1)]
		let thin = DiskNode(directoryNamed: "thin", children: [DiskNode(name: "f", kind: .file, size: 10, itemCount: 1)])
		children.append(thin)
		for index in 0 ..< 5 {
			children.append(DiskNode(name: "tiny\(index)", kind: .file, size: 10, itemCount: 1))
		}
		let root = DiskNode(directoryNamed: "root", children: children)
		let from = SunburstLayout(center: root)
		let rest = try! #require(from.segments.first { $0.depth == 1 && $0.node == nil })
		let transition = SunburstTransition(from: from, to: SunburstLayout(center: thin))
		#expect(transition.zoom == .into(start: rest.start, end: rest.end, depth: 1))
	}
}
