import Foundation

/// One item of a scanned tree: a folder with its children sorted largest first, a file, or the
/// folder's smaller files folded into one entry.
///
/// Immutable and shared by reference. A scan of a whole volume has hundreds of thousands of
/// folders, so the tree is never copied: navigating keeps a chain of nodes from the root, and a
/// deletion rebuilds only the nodes on that chain (`DiskTree.removing`). Two nodes are equal only
/// when they are the same object, which is what TCA's observation needs to notice a rebuilt chain.
public final class DiskNode: Sendable, Identifiable, Equatable {
	public enum Kind: Sendable, Equatable {
		case directory
		case file
		/// The files of a folder below its largest `DiskScanner.filesKeptPerDirectory`, summed.
		case smallerFiles(count: Int)
		/// Space the volume reports as allocated that the scan of it did not find: purgeable
		/// space, the other volumes of its APFS container, and what could not be read. Only a
		/// child of the root of a volume scan, so the centre adds up to what Finder says is used.
		case hiddenSpace(purgeable: Int64, otherVolumes: Int64)
	}

	/// The name of the root's hidden-space entry.
	public static let hiddenSpaceName = "Hidden space"

	/// The item's file name; the root carries the scanned location's full path.
	public let name: String
	public let kind: Kind
	/// Allocated bytes, as `du` counts them.
	public let size: Int64
	/// Files and folders inside a folder, counting folders themselves; 1 for a file.
	public let itemCount: Int
	/// Largest first.
	public let children: [DiskNode]
	/// A folder that could not be read (no permission): its size is unknown and counted as 0.
	public let isInaccessible: Bool

	public var id: ObjectIdentifier { ObjectIdentifier(self) }

	public init(
		name: String,
		kind: Kind,
		size: Int64,
		itemCount: Int,
		children: [DiskNode] = [],
		isInaccessible: Bool = false
	) {
		self.name = name
		self.kind = kind
		self.size = size
		self.itemCount = itemCount
		self.children = children
		self.isInaccessible = isInaccessible
	}

	/// A folder from its children: its size and item count are theirs, summed.
	public convenience init(directoryNamed name: String, children: [DiskNode], isInaccessible: Bool = false) {
		let sorted = children.sorted { $0.size > $1.size }
		self.init(
			name: name,
			kind: .directory,
			size: sorted.reduce(0) { $0 + $1.size },
			itemCount: sorted.reduce(0) { $0 + $1.itemCount + ($1.isDirectory ? 1 : 0) },
			children: sorted,
			isInaccessible: isInaccessible
		)
	}

	public var isDirectory: Bool { kind == .directory }
	public var isHiddenSpace: Bool {
		if case .hiddenSpace = kind { return true }
		return false
	}

	/// Whether the node is one item on disk: the summed smaller files and the hidden space are not.
	public var isOnDisk: Bool {
		switch kind {
		case .directory, .file: true
		case .smallerFiles, .hiddenSpace: false
		}
	}

	/// The hidden space of a volume scan, as the root's child, or nil when the volume reports
	/// no more allocated than the scan found (or the scan was of a folder).
	public static func hiddenSpace(for root: DiskNode, on volume: DiskVolumeUsage) -> DiskNode? {
		let hidden = volume.allocatedCapacity - root.size
		guard hidden > 0 else { return nil }
		let purgeable = min(max(0, volume.purgeableCapacity), hidden)
		let otherVolumes = min(max(0, volume.otherVolumesCapacity), hidden - purgeable)
		return DiskNode(name: hiddenSpaceName, kind: .hiddenSpace(purgeable: purgeable, otherVolumes: otherVolumes), size: hidden, itemCount: 0)
	}

	/// Whether the node can be moved to the Trash or deleted: one item on disk that could be read.
	public var isRemovable: Bool { isOnDisk && !isInaccessible }

	public func child(named name: String) -> DiskNode? {
		children.first { $0.name == name }
	}

	/// The same folder without the named child; the folder's size and count shrink by the child's.
	public func removingChild(named name: String) -> DiskNode {
		DiskNode(directoryNamed: self.name, children: children.filter { $0.name != name }, isInaccessible: isInaccessible)
	}

	/// The same folder with one child swapped for another node.
	public func replacingChild(_ child: DiskNode, with replacement: DiskNode) -> DiskNode {
		DiskNode(
			directoryNamed: name,
			children: children.map { $0 === child ? replacement : $0 },
			isInaccessible: isInaccessible
		)
	}

	public static func == (lhs: DiskNode, rhs: DiskNode) -> Bool {
		lhs === rhs
	}
}

public enum DiskTree {
	/// The chain `[root, …, parent]` rebuilt without `parent`'s named child. Every node on the
	/// chain is replaced, so a view holding the old nodes sees the change; nothing off it is.
	public static func removing(childNamed name: String, from chain: [DiskNode]) -> [DiskNode] {
		guard let parent = chain.last else {
			return chain
		}
		var rebuilt = [parent.removingChild(named: name)]
		for (index, ancestor) in chain.dropLast().enumerated().reversed() {
			rebuilt.insert(ancestor.replacingChild(chain[index + 1], with: rebuilt[0]), at: 0)
		}
		return rebuilt
	}

	/// The on-disk location of the last node of a chain whose first node is the scan root.
	public static func url(of chain: [DiskNode]) -> URL? {
		guard let root = chain.first else {
			return nil
		}
		var url = URL(filePath: root.name, directoryHint: .isDirectory)
		for node in chain.dropFirst() {
			url.append(path: node.name, directoryHint: node.isDirectory ? .isDirectory : .notDirectory)
		}
		return url
	}
}
