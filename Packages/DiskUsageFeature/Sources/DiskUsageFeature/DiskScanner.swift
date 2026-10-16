import CasePaths
import Darwin
import Foundation
import Synchronization

/// How far a scan has got, reported a few times a second while it runs.
public struct DiskScanProgress: Equatable, Sendable {
	public var scannedBytes: Int64 = 0
	public var scannedItems: Int = 0
	public var inaccessibleFolders: Int = 0
	/// The folder being read when the progress was taken.
	public var currentPath: String?

	public init(scannedBytes: Int64 = 0, scannedItems: Int = 0, inaccessibleFolders: Int = 0, currentPath: String? = nil) {
		self.scannedBytes = scannedBytes
		self.scannedItems = scannedItems
		self.inaccessibleFolders = inaccessibleFolders
		self.currentPath = currentPath
	}
}

/// A finished scan: the tree, where it was taken, and what it could not see.
public struct DiskScanResult: Equatable, Sendable {
	public var root: DiskNode
	public var rootURL: URL
	public var inaccessibleFolders: Int
	public var duration: Duration

	public init(root: DiskNode, rootURL: URL, inaccessibleFolders: Int, duration: Duration) {
		self.root = root
		self.rootURL = rootURL
		self.inaccessibleFolders = inaccessibleFolders
		self.duration = duration
	}
}

@CasePathable
public enum DiskScanEvent: Equatable, Sendable {
	case progress(DiskScanProgress)
	case finished(DiskScanResult)
	/// The root itself could not be opened.
	case failed(String)
}

/// Builds a `DiskNode` tree for a folder or volume, counting disk space the way `du` does:
/// allocated blocks, every hard-linked file once, symbolic links not followed, other volumes
/// (mount points) not entered.
///
/// Reads each directory with `getattrlistbulk`, which returns a whole batch of entries'
/// attributes per call, and walks the first two levels of folders side by side — the work is
/// bound by the kernel, so a handful of workers is all that helps. Open descriptors stay at the
/// tree's depth because a folder's subfolders are entered only once the folder has been read.
public nonisolated enum DiskScanner {

	/// Files a folder keeps as nodes of their own; the rest are summed into one
	/// `DiskNode.Kind.smallerFiles` entry. A whole volume has millions of files, and a node for
	/// each would take more memory than the chart could ever show.
	public static let filesKeptPerDirectory = 100

	/// How often progress is reported.
	static let progressInterval: Duration = .milliseconds(150)

	/// Scans `rootURL`, yielding progress until the tree is finished. Cancelling the consumer
	/// stops the scan.
	public static func scan(_ rootURL: URL) -> AsyncStream<DiskScanEvent> {
		AsyncStream { continuation in
			let task = Task.detached(priority: .userInitiated) {
				let start = ContinuousClock.now
				let tally = ScanTally()
				let reporter = Task {
					while !Task.isCancelled {
						try? await Task.sleep(for: progressInterval)
						guard !Task.isCancelled else { break }
						continuation.yield(.progress(tally.snapshot()))
					}
				}
				defer { reporter.cancel() }

				let path = rootURL.path(percentEncoded: false)
				let directory = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
				guard directory >= 0 else {
					continuation.yield(.failed(String(cString: strerror(errno))))
					continuation.finish()
					return
				}

				let root = await walkConcurrently(directory: directory, name: path, path: path, tally: tally, levelsToParallelize: 2)
				guard !Task.isCancelled else {
					continuation.finish()
					return
				}
				continuation.yield(.progress(tally.snapshot()))
				continuation.yield(.finished(DiskScanResult(
					root: root,
					rootURL: rootURL,
					inaccessibleFolders: tally.snapshot().inaccessibleFolders,
					duration: start.duration(to: .now)
				)))
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// Folders walked at once at each of the parallelized levels: eight at the root, two inside
	/// each of those, so at most sixteen workers block in the kernel together.
	private static func workers(forLevel level: Int) -> Int {
		level >= 2 ? 8 : 2
	}

	/// Walks a directory already open, closing it. Its subfolders are walked side by side when
	/// `levelsToParallelize` is above zero, each of them in turn with one level fewer.
	static func walkConcurrently(
		directory: Int32,
		name: String,
		path: String,
		tally: ScanTally,
		levelsToParallelize: Int
	) async -> DiskNode {
		guard levelsToParallelize > 0 else {
			return DirectoryWalker(tally: tally).walk(directory: directory, name: name, path: path)
		}
		tally.enter(path)
		let listing = DirectoryWalker(tally: tally).read(directory: directory)
		var children = listing.fileNodes
		await withTaskGroup(of: DiskNode.self) { group in
			var pending = listing.subdirectories.makeIterator()
			func addNext() {
				guard let subdirectory = pending.next() else { return }
				group.addTask {
					let subpath = path.hasSuffix("/") ? path + subdirectory : path + "/" + subdirectory
					let fd = openat(directory, subdirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
					guard fd >= 0 else {
						tally.recordInaccessible()
						return DiskNode(name: subdirectory, kind: .directory, size: 0, itemCount: 0, isInaccessible: true)
					}
					return await walkConcurrently(
						directory: fd, name: subdirectory, path: subpath, tally: tally, levelsToParallelize: levelsToParallelize - 1
					)
				}
			}
			for _ in 0 ..< workers(forLevel: levelsToParallelize) {
				addNext()
			}
			for await child in group {
				children.append(child)
				addNext()
			}
		}
		close(directory)
		return DiskNode(directoryNamed: name, children: children, isInaccessible: listing.isInaccessible)
	}
}

/// The running totals every worker adds to, and the progress reporter reads.
final class ScanTally: Sendable {
	private struct Totals {
		var bytes: Int64 = 0
		var items = 0
		var inaccessible = 0
		var currentPath: String?
		/// File ids of hard-linked files already counted; shared by every worker so a file
		/// linked from two branches is counted once.
		var hardLinksSeen = Set<UInt64>()
	}

	private let totals = Mutex(Totals())

	func enter(_ path: String) {
		totals.withLock { $0.currentPath = path }
	}

	func add(bytes: Int64, items: Int) {
		totals.withLock {
			$0.bytes += bytes
			$0.items += items
		}
	}

	func recordInaccessible() {
		totals.withLock { $0.inaccessible += 1 }
	}

	/// Whether a hard-linked file is seen for the first time.
	func isFirstSighting(ofHardLink fileID: UInt64) -> Bool {
		totals.withLock { $0.hardLinksSeen.insert(fileID).inserted }
	}

	func snapshot() -> DiskScanProgress {
		totals.withLock {
			DiskScanProgress(scannedBytes: $0.bytes, scannedItems: $0.items, inaccessibleFolders: $0.inaccessible, currentPath: $0.currentPath)
		}
	}
}

/// Reads directories with `getattrlistbulk` and builds their nodes.
nonisolated final class DirectoryWalker {
	struct Listing {
		var subdirectories: [String] = []
		var fileNodes: [DiskNode] = []
		var isInaccessible = false
	}

	private let tally: ScanTally
	private let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
	private static let bufferSize = 256 * 1024

	init(tally: ScanTally) {
		self.tally = tally
	}

	deinit {
		buffer.deallocate()
	}

	/// Walks a directory already open, and closes it.
	func walk(directory: Int32, name: String, path: String) -> DiskNode {
		tally.enter(path)
		let listing = read(directory: directory)
		var children = listing.fileNodes
		for subdirectory in listing.subdirectories where !Task.isCancelled {
			let subpath = path.hasSuffix("/") ? path + subdirectory : path + "/" + subdirectory
			let fd = openat(directory, subdirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard fd >= 0 else {
				tally.recordInaccessible()
				children.append(DiskNode(name: subdirectory, kind: .directory, size: 0, itemCount: 0, isInaccessible: true))
				continue
			}
			children.append(walk(directory: fd, name: subdirectory, path: subpath))
		}
		close(directory)
		return DiskNode(directoryNamed: name, children: children, isInaccessible: listing.isInaccessible)
	}

	/// Reads one open directory: the names of its subfolders (mount points left out) and its
	/// files as nodes, the smaller ones summed. Does not close the directory.
	func read(directory: Int32) -> Listing {
		var attributes = attrlist()
		attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
		attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
			| attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
		attributes.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
		attributes.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

		var listing = Listing()
		var files: [(name: String, size: Int64)] = []
		var readAnything = false
		while !Task.isCancelled {
			// The common attributes are always packed; a directory's entry carries only the
			// directory group and anything else's only the file group.
			let count = getattrlistbulk(directory, &attributes, buffer, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
			if count < 0, !readAnything {
				listing.isInaccessible = true
				tally.recordInaccessible()
			}
			guard count > 0 else { break }
			readAnything = true
			var batchBytes: Int64 = 0
			var entry = buffer
			for _ in 0 ..< count {
				let length = entry.loadUnaligned(as: UInt32.self)
				let returned = entry.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
				let nameReference = entry + 4 + MemoryLayout<attribute_set_t>.size
				let nameOffset = Int(nameReference.loadUnaligned(as: Int32.self))
				let name = String(cString: (nameReference + nameOffset).assumingMemoryBound(to: CChar.self))
				let objectType = nameReference.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
				let fileID = nameReference.loadUnaligned(fromByteOffset: 12, as: UInt64.self)
				let groupAttributes = nameReference + 20

				if objectType == VDIR.rawValue {
					let mountStatus = groupAttributes.loadUnaligned(as: UInt32.self)
					if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0,
					   mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) == 0 {
						listing.subdirectories.append(name)
					}
				}
				else {
					var allocatedSize: Int64 = 0
					if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
						let linkCount = groupAttributes.loadUnaligned(as: UInt32.self)
						let size = groupAttributes.loadUnaligned(fromByteOffset: 4, as: Int64.self)
						if linkCount <= 1 || tally.isFirstSighting(ofHardLink: fileID) {
							allocatedSize = size
						}
					}
					files.append((name, allocatedSize))
					batchBytes += allocatedSize
				}
				entry += Int(length)
			}
			tally.add(bytes: batchBytes, items: Int(count))
		}

		files.sort { $0.size > $1.size }
		let kept = files.prefix(DiskScanner.filesKeptPerDirectory)
		listing.fileNodes = kept.map { DiskNode(name: $0.name, kind: .file, size: $0.size, itemCount: 1) }
		let rest = files.dropFirst(DiskScanner.filesKeptPerDirectory)
		if !rest.isEmpty {
			listing.fileNodes.append(DiskNode(
				name: "\(rest.count) smaller files",
				kind: .smallerFiles(count: rest.count),
				size: rest.reduce(0) { $0 + $1.size },
				itemCount: rest.count
			))
		}
		return listing
	}
}
