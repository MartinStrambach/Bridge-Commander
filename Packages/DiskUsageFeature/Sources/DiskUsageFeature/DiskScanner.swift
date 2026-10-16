import CasePaths
import Darwin
import Dispatch
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
/// attributes per call. The folders still to be read wait in one `ScanWorkQueue` that
/// `workerCount` threads take from, so every worker stays busy until the last folder is read
/// however unevenly the tree is shaped; a fixed fan-out at the top levels left one worker with
/// most of a volume (`~/Library/Developer`: 71 s against 12 s, 2026-10-16). The tree is put
/// together from the bottom as folders finish, in any order (`FolderInProgress`).
public nonisolated enum DiskScanner {

	/// Files a folder keeps as nodes of their own; the rest are summed into one
	/// `DiskNode.Kind.smallerFiles` entry. A whole volume has millions of files, and a node for
	/// each would take more memory than the chart could ever show.
	public static let filesKeptPerDirectory = 100

	/// Threads reading folders at once. The work is in the kernel, which serves this many
	/// directory reads side by side; more gained nothing measurable.
	static let workerCount = 16

	/// How often progress is reported.
	static let progressInterval: Duration = .milliseconds(150)

	/// Scans `rootURL`, yielding progress until the tree is finished. Cancelling the consumer
	/// stops the scan.
	public static func scan(_ rootURL: URL) -> AsyncStream<DiskScanEvent> {
		scan(rootURL, workers: workerCount)
	}

	static func scan(_ rootURL: URL, workers: Int) -> AsyncStream<DiskScanEvent> {
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

				let root = FolderInProgress(name: path, path: path, parent: nil)
				let queue = ScanWorkQueue()
				queue.push(.init(folder: root, parent: nil, rootDescriptor: directory))
				await withTaskCancellationHandler {
					await runWorkers(count: workers, queue: queue, tally: tally)
				} onCancel: {
					queue.cancel()
				}
				// Folders left unread by a cancelled scan still hold their parents' descriptors.
				for item in queue.drain() {
					if let parent = item.parent {
						parent.subfolderOpened()
					}
					else if let rootDescriptor = item.rootDescriptor {
						close(rootDescriptor)
					}
				}
				guard !Task.isCancelled, let node = root.finishedNode else {
					continuation.finish()
					return
				}
				continuation.yield(.progress(tally.snapshot()))
				continuation.yield(.finished(DiskScanResult(
					root: node,
					rootURL: rootURL,
					inaccessibleFolders: tally.snapshot().inaccessibleFolders,
					duration: start.duration(to: .now)
				)))
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// Starts `count` threads reading folders from `queue` and returns once all have exited,
	/// which is when the queue is empty and no worker is still reading, or the scan was cancelled.
	/// Threads rather than tasks: a worker spends its time blocked in the kernel, and that many
	/// blocked tasks would leave the cooperative pool with little room for anything else.
	private static func runWorkers(count: Int, queue: ScanWorkQueue, tally: ScanTally) async {
		await withCheckedContinuation { continuation in
			let exited = DispatchGroup()
			for index in 0 ..< count {
				exited.enter()
				let thread = Thread {
					ScanWorker(queue: queue, tally: tally).run()
					exited.leave()
				}
				thread.name = "DiskScanner.worker\(index)"
				thread.qualityOfService = .userInitiated
				thread.start()
			}
			exited.notify(queue: .global()) { continuation.resume() }
		}
	}
}

/// A folder the scan has reached but not finished: what it has been read to hold, and how many
/// of its subfolders are still to be read. Becomes a `DiskNode` once the last one has finished,
/// which may be long after the folder itself was read, and hands it to its parent.
///
/// The folder's descriptor stays open until each subfolder has been opened from it: with
/// `openat`, a subfolder costs the kernel one lookup instead of one per path component. The
/// queue is last-in-first-out, so a worker goes deep before wide and the open descriptors are
/// about the tree's depth per worker, not the queue's length (a GUI app's soft limit is 256).
nonisolated final class FolderInProgress: Sendable {
	let name: String
	let path: String
	let parent: FolderInProgress?

	private struct State {
		var descriptor: Int32 = -1
		var subfoldersToOpen = 0
		var subfoldersToFinish = 0
		var isRead = false
		var isInaccessible = false
		var children: [DiskNode] = []
		var node: DiskNode?
	}

	private let state = Mutex(State())

	init(name: String, path: String, parent: FolderInProgress?) {
		self.name = name
		self.path = path
		self.parent = parent
	}

	/// The root's finished tree, once the scan is done.
	var finishedNode: DiskNode? {
		state.withLock { $0.node }
	}

	/// The folder's open descriptor while any subfolder is still to be opened from it.
	var descriptor: Int32 {
		state.withLock { $0.descriptor }
	}

	/// Records what reading the folder found. Its subfolders, `count` of them, are opened and
	/// read later; the folder is complete at once when there are none.
	func didRead(_ listing: DirectoryWalker.Listing, subfolders count: Int, descriptor: Int32) {
		let isComplete = state.withLock {
			$0.descriptor = descriptor
			$0.children = listing.leafNodes
			$0.isInaccessible = listing.isInaccessible
			$0.subfoldersToOpen = count
			$0.subfoldersToFinish = count
			$0.isRead = true
			return count == 0
		}
		if isComplete {
			close(descriptor)
			complete()
		}
	}

	/// A subfolder has been opened (or failed to open); the descriptor is closed with the last.
	func subfolderOpened() {
		let descriptorToClose: Int32? = state.withLock {
			$0.subfoldersToOpen -= 1
			guard $0.subfoldersToOpen == 0 else { return nil }
			defer { $0.descriptor = -1 }
			return $0.descriptor
		}
		if let descriptorToClose {
			close(descriptorToClose)
		}
	}

	/// A subfolder's tree is done; the folder's own is, once this was the last.
	func subfolderFinished(_ node: DiskNode) {
		let isComplete = state.withLock {
			$0.children.append(node)
			$0.subfoldersToFinish -= 1
			return $0.isRead && $0.subfoldersToFinish == 0
		}
		if isComplete {
			complete()
		}
	}

	private func complete() {
		let (children, isInaccessible) = state.withLock { ($0.children, $0.isInaccessible) }
		let node = DiskNode(directoryNamed: name, children: children, isInaccessible: isInaccessible)
		if let parent {
			parent.subfolderFinished(node)
		}
		else {
			state.withLock { $0.node = node }
		}
	}
}

/// A folder waiting to be read: opened from its parent's descriptor, or already open for the root.
nonisolated struct ScanWorkItem {
	let folder: FolderInProgress
	let parent: FolderInProgress?
	let rootDescriptor: Int32?
}

/// The folders still to be read, shared by the workers, last in first out. A worker that finds
/// it empty waits while another is still reading, since that one may add more; the queue is done
/// when it is empty and no worker is reading.
///
/// `NSCondition` because the workers are threads that must block until there is work, which
/// `Mutex` has no way to do.
nonisolated final class ScanWorkQueue: @unchecked Sendable {
	private let condition = NSCondition()
	private var pending: [ScanWorkItem] = []
	private var readingWorkers = 0
	private let cancelled = Atomic(false)

	var isCancelled: Bool {
		cancelled.load(ordering: .relaxed)
	}

	func push(_ item: ScanWorkItem) {
		condition.lock()
		pending.append(item)
		condition.signal()
		condition.unlock()
	}

	/// The next folder to read, waiting for one while any worker is still reading. Nil once the
	/// scan is done or cancelled. Every item taken must be followed by `finished()`.
	func next() -> ScanWorkItem? {
		condition.lock()
		defer { condition.unlock() }
		while true {
			if isCancelled {
				return nil
			}
			if let item = pending.popLast() {
				readingWorkers += 1
				return item
			}
			if readingWorkers == 0 {
				return nil
			}
			condition.wait()
		}
	}

	func finished() {
		condition.lock()
		readingWorkers -= 1
		if readingWorkers == 0 {
			condition.broadcast()
		}
		condition.unlock()
	}

	func cancel() {
		condition.lock()
		cancelled.store(true, ordering: .relaxed)
		condition.broadcast()
		condition.unlock()
	}

	/// Takes whatever is still queued; empty unless the scan was cancelled.
	func drain() -> [ScanWorkItem] {
		condition.lock()
		defer { condition.unlock() }
		let remaining = pending
		pending.removeAll()
		return remaining
	}
}

/// One thread of the scan: reads folders from the queue until it runs dry.
nonisolated struct ScanWorker {
	let queue: ScanWorkQueue
	let tally: ScanTally

	func run() {
		let walker = DirectoryWalker(tally: tally) { [queue] in queue.isCancelled }
		while let item = queue.next() {
			read(item, with: walker)
			queue.finished()
		}
	}

	private func read(_ item: ScanWorkItem, with walker: DirectoryWalker) {
		let folder = item.folder
		let descriptor: Int32
		if let parent = item.parent {
			descriptor = openat(parent.descriptor, folder.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			parent.subfolderOpened()
			guard descriptor >= 0 else {
				tally.recordInaccessible()
				parent.subfolderFinished(DiskNode(name: folder.name, kind: .directory, size: 0, itemCount: 0, isInaccessible: true))
				return
			}
		}
		else {
			descriptor = item.rootDescriptor ?? -1
		}
		tally.enter(folder.path)
		let listing = walker.read(directory: descriptor)
		let subfolders = listing.subdirectories.map { name in
			FolderInProgress(name: name, path: folder.path.hasSuffix("/") ? folder.path + name : folder.path + "/" + name, parent: folder)
		}
		// The count is recorded before any subfolder is queued, so none can finish first.
		folder.didRead(listing, subfolders: subfolders.count, descriptor: descriptor)
		for subfolder in subfolders {
			queue.push(.init(folder: subfolder, parent: folder, rootDescriptor: nil))
		}
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
		/// Subfolders still to be read.
		var subdirectories: [String] = []
		/// Children known without reading further: files, the summed smaller files, empty folders.
		var leafNodes: [DiskNode] = []
		var isInaccessible = false
	}

	private let tally: ScanTally
	private let isCancelled: () -> Bool
	private let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
	private static let bufferSize = 256 * 1024

	init(tally: ScanTally, isCancelled: @escaping () -> Bool = { false }) {
		self.tally = tally
		self.isCancelled = isCancelled
	}

	deinit {
		buffer.deallocate()
	}

	/// Reads one open directory: the names of its subfolders still to be read (mount points and
	/// empty folders left out), and its files and empty subfolders as nodes, the smaller files
	/// summed. Does not close the directory.
	///
	/// Entries are parsed by the attributes each reports as returned rather than at fixed
	/// offsets, so a file system that cannot tell a folder's entry count (or a file's id) is
	/// told apart from one reporting zero: an unknown count means the folder is read as usual.
	func read(directory: Int32) -> Listing {
		var attributes = attrlist()
		attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
		attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
			| attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
		attributes.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT) | attrgroup_t(ATTR_DIR_MOUNTSTATUS)
		attributes.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

		var listing = Listing()
		var files: [(name: String, size: Int64)] = []
		var readAnything = false
		while !isCancelled() {
			let count = getattrlistbulk(directory, &attributes, buffer, Self.bufferSize, 0)
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
				// Attributes follow in bit order, each present only when reported as returned.
				var cursor = entry + 4 + MemoryLayout<attribute_set_t>.size
				func take<T>(_ bit: Int32, of group: attrgroup_t, as type: T.Type) -> T? {
					guard group & attrgroup_t(bit) != 0 else { return nil }
					defer { cursor += MemoryLayout<T>.size }
					return cursor.loadUnaligned(as: T.self)
				}
				var name = ""
				if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
					let nameOffset = Int(cursor.loadUnaligned(as: Int32.self))
					name = String(cString: (cursor + nameOffset).assumingMemoryBound(to: CChar.self))
					cursor += MemoryLayout<attrreference_t>.size
				}
				let objectType = take(ATTR_CMN_OBJTYPE, of: returned.commonattr, as: UInt32.self)
				let fileID = take(ATTR_CMN_FILEID, of: returned.commonattr, as: UInt64.self)

				if objectType == VDIR.rawValue {
					let entryCount = take(ATTR_DIR_ENTRYCOUNT, of: returned.dirattr, as: UInt32.self)
					let mountStatus = take(ATTR_DIR_MOUNTSTATUS, of: returned.dirattr, as: UInt32.self) ?? 0
					if mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 {
						// Another volume: not entered, like `du -x`.
					}
					else if entryCount == 0 {
						// Empty, so there is nothing to open it for: most of a DerivedData tree.
						listing.leafNodes.append(DiskNode(name: name, kind: .directory, size: 0, itemCount: 0))
					}
					else {
						listing.subdirectories.append(name)
					}
				}
				else {
					let linkCount = take(ATTR_FILE_LINKCOUNT, of: returned.fileattr, as: UInt32.self) ?? 1
					let size = take(ATTR_FILE_ALLOCSIZE, of: returned.fileattr, as: Int64.self) ?? 0
					// A hard-linked file counts once; without an id to tell the links apart, each counts.
					let isCountedHere = linkCount <= 1 || fileID.map { tally.isFirstSighting(ofHardLink: $0) } ?? true
					let allocatedSize = isCountedHere ? size : 0
					files.append((name, allocatedSize))
					batchBytes += allocatedSize
				}
				entry += Int(length)
			}
			tally.add(bytes: batchBytes, items: Int(count))
		}

		files.sort { $0.size > $1.size }
		let kept = files.prefix(DiskScanner.filesKeptPerDirectory)
		listing.leafNodes += kept.map { DiskNode(name: $0.name, kind: .file, size: $0.size, itemCount: 1) }
		let rest = files.dropFirst(DiskScanner.filesKeptPerDirectory)
		if !rest.isEmpty {
			listing.leafNodes.append(DiskNode(
				name: "\(rest.count) smaller files",
				kind: .smallerFiles(count: rest.count),
				size: rest.reduce(0) { $0 + $1.size },
				itemCount: rest.count
			))
		}
		return listing
	}
}
