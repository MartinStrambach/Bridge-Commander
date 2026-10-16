import Foundation
import Testing
@testable import DiskUsageFeature

@Suite("Disk tree")
struct DiskNodeTests {
	private func tree() -> [DiskNode] {
		let big = DiskNode(name: "big.bin", kind: .file, size: 600, itemCount: 1)
		let small = DiskNode(name: "small.txt", kind: .file, size: 100, itemCount: 1)
		let cache = DiskNode(directoryNamed: "Cache", children: [big, small])
		let notes = DiskNode(name: "notes.md", kind: .file, size: 50, itemCount: 1)
		let library = DiskNode(directoryNamed: "Library", children: [notes, cache])
		let root = DiskNode(directoryNamed: "/Users/me", children: [library])
		return [root, library, cache]
	}

	@Test("a folder sums its children and sorts them largest first")
	func directorySums() {
		let chain = tree()
		#expect(chain[0].size == 750)
		#expect(chain[0].itemCount == 5)
		#expect(chain[1].children.map(\.name) == ["Cache", "notes.md"])
	}

	@Test("removing a child rebuilds every node on the chain and nothing else")
	func removingRebuildsChain() {
		let chain = tree()
		let rebuilt = DiskTree.removing(childNamed: "big.bin", from: chain)

		#expect(rebuilt.count == 3)
		#expect(rebuilt.map(\.name) == ["/Users/me", "Library", "Cache"])
		#expect(rebuilt[2].children.map(\.name) == ["small.txt"])
		#expect(rebuilt[0].size == 150)
		#expect(rebuilt[0].itemCount == 4)
		// New objects on the chain…
		#expect(rebuilt[0] !== chain[0])
		#expect(rebuilt[1] !== chain[1])
		// …and the untouched sibling is the same one.
		#expect(rebuilt[1].child(named: "notes.md") === chain[1].child(named: "notes.md"))
	}

	@Test("a chain's location is the root path plus the names below it")
	func chainURL() {
		let chain = tree()
		#expect(DiskTree.url(of: chain)?.path(percentEncoded: false) == "/Users/me/Library/Cache/")
		#expect(DiskTree.url(of: chain + [chain[2].children[0]])?.path(percentEncoded: false) == "/Users/me/Library/Cache/big.bin")
		#expect(DiskTree.url(of: []) == nil)
	}

	@Test("hidden space is the volume's allocation beyond the scan, split as far as the parts go")
	func hiddenSpace() {
		let root = DiskNode(directoryNamed: "/", children: [DiskNode(name: "a", kind: .file, size: 700, itemCount: 1)])
		#expect(DiskNode.hiddenSpace(for: root, on: .init(allocatedCapacity: 700, purgeableCapacity: 10, otherVolumesCapacity: 10)) == nil)
		#expect(DiskNode.hiddenSpace(for: root, on: .init(allocatedCapacity: 600, purgeableCapacity: 0, otherVolumesCapacity: 0)) == nil)
		let hidden = DiskNode.hiddenSpace(for: root, on: .init(allocatedCapacity: 1000, purgeableCapacity: 200, otherVolumesCapacity: 150))
		#expect(hidden?.size == 300)
		// Purgeable first, then the other volumes, each capped by what is left.
		#expect(hidden?.kind == .hiddenSpace(purgeable: 200, otherVolumes: 100))
		#expect(hidden?.isHiddenSpace == true)
		#expect(hidden?.isOnDisk == false)
		#expect(hidden?.isRemovable == false)
		let withHidden = DiskNode(directoryNamed: "/", children: root.children + [hidden!])
		#expect(withHidden.size == 1000)
		#expect(withHidden.itemCount == 1)
	}

	@Test("the summed smaller files are not one item on disk")
	func smallerFilesAreNotRemovable() {
		let rest = DiskNode(name: "12 smaller files", kind: .smallerFiles(count: 12), size: 10, itemCount: 12)
		let locked = DiskNode(name: "Mail", kind: .directory, size: 0, itemCount: 0, isInaccessible: true)
		#expect(!rest.isOnDisk)
		#expect(!rest.isRemovable)
		#expect(locked.isOnDisk)
		#expect(!locked.isRemovable)
	}
}
