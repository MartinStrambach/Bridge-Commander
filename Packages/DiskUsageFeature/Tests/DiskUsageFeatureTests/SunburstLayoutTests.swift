import Foundation
import Testing
@testable import DiskUsageFeature

@Suite("Sunburst layout")
struct SunburstLayoutTests {
	@Test("children share the circle by size, clockwise from the top, largest first")
	func sharesBySize() {
		let center = DiskNode(directoryNamed: "root", children: [
			DiskNode(name: "a", kind: .file, size: 500, itemCount: 1),
			DiskNode(name: "b", kind: .file, size: 250, itemCount: 1),
			DiskNode(name: "c", kind: .file, size: 250, itemCount: 1),
		])
		let layout = SunburstLayout(center: center)
		let firstRing = layout.segments.filter { $0.depth == 1 }
		#expect(firstRing.map { $0.node?.name } == ["a", "b", "c"])
		#expect(firstRing.map(\.start) == [0, 0.5, 0.75])
		#expect(firstRing.last?.end == 1)
	}

	@Test("children too thin to draw are summed into one trailing segment")
	func tinyChildrenAreSummed() {
		var children = [DiskNode(name: "big", kind: .file, size: 1_000_000, itemCount: 1)]
		for index in 0 ..< 20 {
			children.append(DiskNode(name: "tiny\(index)", kind: .file, size: 10, itemCount: 1))
		}
		let layout = SunburstLayout(center: DiskNode(directoryNamed: "root", children: children))
		let firstRing = layout.segments.filter { $0.depth == 1 }
		#expect(firstRing.count == 2)
		#expect(firstRing[1].content == .rest(count: 20, size: 200))
		#expect(abs(firstRing[1].end - 1) < 1e-9)
		#expect(layout.segment(forChildNamed: "tiny3") == nil)
	}

	@Test("folders are laid out in deeper rings up to the depth limit, with their ancestry")
	func descendsIntoFolders() {
		var node = DiskNode(name: "leaf", kind: .file, size: 100, itemCount: 1)
		for level in 1 ... 8 {
			node = DiskNode(directoryNamed: "d\(level)", children: [node])
		}
		let layout = SunburstLayout(center: node, maxDepth: 4)
		#expect(layout.segments.map(\.depth) == [1, 2, 3, 4])
		#expect(layout.segments.last?.ancestry.map(\.name) == ["d7", "d6", "d5", "d4"])
		#expect(layout.segment(atAngle: 0.3, depth: 3)?.node?.name == "d5")
		#expect(layout.segment(atAngle: 0.3, depth: 5) == nil)
	}

	@Test("an angle past a full turn wraps")
	func angleWraps() {
		let center = DiskNode(directoryNamed: "root", children: [
			DiskNode(name: "a", kind: .file, size: 1, itemCount: 1),
			DiskNode(name: "b", kind: .file, size: 1, itemCount: 1),
		])
		let layout = SunburstLayout(center: center)
		#expect(layout.segment(atAngle: 1.25, depth: 1)?.node?.name == "a")
		#expect(layout.segment(atAngle: 0.75, depth: 1)?.node?.name == "b")
	}
}
