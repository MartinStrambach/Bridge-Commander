import Darwin
import Foundation

/// How Xcode's DerivedData folder splits into folders that still serve a project and folders
/// that only take up space. Built up folder by folder while it is measured, so a partial value
/// is shown during a scan that can take a minute.
public struct DerivedDataUsage: Equatable, Sendable {
	public enum Kind: CaseIterable, Sendable {
		/// A project folder whose workspace still exists.
		case inUse
		/// A project folder whose workspace is gone: a deleted worktree or a temporary checkout.
		case orphaned
		/// A project folder without an `info.plist`, so its workspace cannot be told: what is
		/// left after the folder was deleted while Xcode still had the project open.
		case leftover
		/// Caches shared by every project (`ModuleCache.noindex`, `CompilationCache.noindex`, …).
		case sharedCache
	}

	public struct Tally: Equatable, Sendable {
		public var folders: Int
		public var bytes: Int64

		public init(folders: Int = 0, bytes: Int64 = 0) {
			self.folders = folders
			self.bytes = bytes
		}
	}

	/// One folder as the measurement saw it; `bytes` is nil until the folder has been measured.
	public struct Folder: Equatable, Sendable {
		public var kind: Kind
		public var bytes: Int64?

		public init(kind: Kind, bytes: Int64? = nil) {
			self.kind = kind
			self.bytes = bytes
		}
	}

	public var tallies: [Kind: Tally]
	public var measuredFolders: Int
	public var totalFolders: Int
	/// Every folder by name, so deleted folders can be taken out of the tallies without
	/// measuring DerivedData again.
	public var folders: [String: Folder]

	public init(
		tallies: [Kind: Tally] = [:],
		measuredFolders: Int = 0,
		totalFolders: Int = 0,
		folders: [String: Folder] = [:]
	) {
		self.tallies = tallies
		self.measuredFolders = measuredFolders
		self.totalFolders = totalFolders
		self.folders = folders
	}

	public var isComplete: Bool { measuredFolders == totalFolders }
	public var totalBytes: Int64 { tallies.values.reduce(0) { $0 + $1.bytes } }

	public subscript(kind: Kind) -> Tally {
		tallies[kind] ?? Tally()
	}

	/// Takes deleted folders out of the tallies, with the kind and size they were measured with.
	/// A folder the measurement never saw (created after it) is ignored.
	public mutating func removeFolders(named names: [String]) {
		for name in names {
			guard let folder = folders.removeValue(forKey: name) else { continue }
			tallies[folder.kind, default: .init()].folders -= 1
			totalFolders -= 1
			if let bytes = folder.bytes {
				tallies[folder.kind, default: .init()].bytes -= bytes
				measuredFolders -= 1
			}
		}
	}
}

/// What deleting one kind of DerivedData folder did.
public struct DerivedDataDeletion: Equatable, Sendable {
	/// The names of the folders removed.
	public var deletedFolders: [String]
	/// One description per folder that could not be removed.
	public var failures: [String]

	public init(deletedFolders: [String] = [], failures: [String] = []) {
		self.deletedFolders = deletedFolders
		self.failures = failures
	}
}

public nonisolated enum DerivedDataUsageScanner {

	/// Folders measured at once. Reading metadata is bound by the kernel, not the disk: on a
	/// 168 GB DerivedData folder of 2.2 million items, eight took 7 s where four took 10 s and
	/// `du -sk` 40 s; more than eight gained nothing (checked 2026-10-15 on 18 cores).
	private static let concurrentMeasurements = 8

	/// Classifies every DerivedData folder, then measures them, yielding the usage after each.
	/// The deletable kinds are measured first, so the sizes that can be acted on settle first.
	public static func measure(in derivedDataURL: URL = defaultDerivedDataURL) -> AsyncStream<DerivedDataUsage> {
		AsyncStream { continuation in
			let task = Task {
				let classified = classifyFolders(in: derivedDataURL)
				let folders = classified.filter { deletableKinds.contains($0.kind) }
					+ classified.filter { !deletableKinds.contains($0.kind) }
				var usage = DerivedDataUsage(totalFolders: folders.count)
				for folder in folders {
					usage.tallies[folder.kind, default: .init()].folders += 1
					usage.folders[folder.url.lastPathComponent] = .init(kind: folder.kind)
				}
				continuation.yield(usage)

				await withTaskGroup(of: (String, DerivedDataUsage.Kind, Int64).self) { group in
					var pending = folders.makeIterator()
					func addNext() {
						guard let folder = pending.next() else { return }
						group.addTask { (folder.url.lastPathComponent, folder.kind, allocatedBytes(at: folder.url)) }
					}
					for _ in 0 ..< concurrentMeasurements {
						addNext()
					}
					for await (name, kind, bytes) in group {
						usage.tallies[kind, default: .init()].bytes += bytes
						usage.folders[name]?.bytes = bytes
						usage.measuredFolders += 1
						continuation.yield(usage)
						addNext()
					}
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// Kinds whose folders serve no existing project, so deleting them costs at most a rebuild
	/// should the project come back.
	public static let deletableKinds: Set<DerivedDataUsage.Kind> = [.orphaned, .leftover]

	/// Items removed at once while folders are deleted. Removing a folder unlinks its files one
	/// after another, about 6 s for a 7 GB project folder of 170 000 items; spreading two such
	/// folders' contents over eight workers took 5.4 s where removing them in turn took 12.7 s
	/// (checked 2026-10-15).
	private static let concurrentRemovals = 8

	/// Deletes every folder of a deletable kind. The folders are classified again here rather
	/// than taken from the last measurement, so a folder whose workspace has reappeared since
	/// (a worktree recreated at the same path) is kept.
	///
	/// The folders' subfolders are emptied first, many items at once; the folders themselves are
	/// then removed one by one through `XcodeDerivedDataHelper.removeFolder`, whose fallback
	/// deals with anything the first pass could not remove.
	public static func deleteFolders(
		of kind: DerivedDataUsage.Kind,
		in derivedDataURL: URL = defaultDerivedDataURL
	) async -> DerivedDataDeletion {
		guard deletableKinds.contains(kind) else {
			return DerivedDataDeletion()
		}
		let folderURLs = classifyFolders(in: derivedDataURL).filter { $0.kind == kind }.map(\.url)
		await removeConcurrently(folderURLs.flatMap(subfolderContents(of:)))

		var deletion = DerivedDataDeletion()
		for folderURL in folderURLs {
			do {
				try XcodeDerivedDataHelper.removeFolder(at: folderURL)
				deletion.deletedFolders.append(folderURL.lastPathComponent)
			}
			catch {
				deletion.failures.append(error.localizedDescription)
			}
		}
		return deletion
	}

	/// The items one level inside a folder's subfolders: small enough pieces to remove side by
	/// side, while the folder's own files (`info.plist`) stay until the folder itself goes.
	static func subfolderContents(of folderURL: URL) -> [URL] {
		let fileManager = FileManager.default
		let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
		let children = (try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Array(keys))) ?? []
		return children.flatMap { child -> [URL] in
			guard
				let values = try? child.resourceValues(forKeys: keys),
				values.isDirectory == true, values.isSymbolicLink != true
			else {
				return []
			}
			return (try? fileManager.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
		}
	}

	/// Removes the items `concurrentRemovals` at a time. Failures are left for the caller's
	/// removal of the enclosing folder to report.
	private static func removeConcurrently(_ itemURLs: [URL]) async {
		await withTaskGroup(of: Void.self) { group in
			var pending = itemURLs.makeIterator()
			func addNext() {
				guard let itemURL = pending.next() else { return }
				group.addTask { try? FileManager.default.removeItem(at: itemURL) }
			}
			for _ in 0 ..< concurrentRemovals {
				addNext()
			}
			for await _ in group {
				addNext()
			}
		}
	}

	public static var defaultDerivedDataURL: URL {
		FileManager.default
			.homeDirectoryForCurrentUser
			.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
	}

	static func classifyFolders(in derivedDataURL: URL) -> [(url: URL, kind: DerivedDataUsage.Kind)] {
		let fileManager = FileManager.default
		let folderURLs = (try? fileManager.contentsOfDirectory(
			at: derivedDataURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: .skipsHiddenFiles
		)) ?? []

		return folderURLs
			.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
			.map { folderURL in
				let workspacePath = workspacePath(ofFolderAt: folderURL)
				let kind = kind(
					folderName: folderURL.lastPathComponent,
					workspacePath: workspacePath,
					workspaceExists: workspacePath.map { fileManager.fileExists(atPath: $0) } ?? false
				)
				return (folderURL, kind)
			}
	}

	static func workspacePath(ofFolderAt folderURL: URL) -> String? {
		guard
			let data = try? Data(contentsOf: folderURL.appending(path: "info.plist", directoryHint: .notDirectory)),
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
		else {
			return nil
		}
		return plist["WorkspacePath"] as? String
	}

	static func kind(folderName: String, workspacePath: String?, workspaceExists: Bool) -> DerivedDataUsage.Kind {
		if workspacePath != nil {
			return workspaceExists ? .inUse : .orphaned
		}
		return isProjectFolderName(folderName) ? .leftover : .sharedCache
	}

	/// Xcode names a project's folder `<name>-<28 lowercase letters>`, the letters derived
	/// from the workspace path; the shared caches have plain names.
	static func isProjectFolderName(_ name: String) -> Bool {
		guard let dash = name.lastIndex(of: "-"), dash != name.startIndex else {
			return false
		}
		let suffix = name[name.index(after: dash)...]
		return suffix.count == 28 && suffix.allSatisfy { ("a" ... "z").contains($0) }
	}

	/// The disk space a folder takes, counted the way `du` counts it: allocated blocks, every
	/// hard-linked file once, symbolic links not followed, other volumes not entered. Stops early
	/// when the task is cancelled.
	static func allocatedBytes(at url: URL) -> Int64 {
		let directory = open(url.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard directory >= 0 else {
			return 0
		}
		let walk = AllocatedSizeWalk()
		walk.add(directory: directory)
		return walk.total
	}
}

/// Sums allocated sizes with `getattrlistbulk`, which returns the attributes of a whole batch of
/// directory entries per call where `fts` makes one `lstat` call per entry: about a quarter
/// faster on DerivedData.
private nonisolated final class AllocatedSizeWalk {
	private(set) var total: Int64 = 0
	private var hardLinksSeen = Set<UInt64>()
	private var entriesRead = 0
	private var isCancelled = false
	private let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
	private static let bufferSize = 256 * 1024

	deinit {
		buffer.deallocate()
	}

	/// Adds the directory's contents and closes it. Subdirectories are entered only once the
	/// directory has been read, so the open descriptors never exceed the depth of the tree.
	func add(directory: Int32) {
		defer { close(directory) }
		var attributes = attrlist()
		attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
		attributes.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
			| attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FILEID)
		attributes.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
		attributes.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

		var subdirectoryNames: [String] = []
		while !isCancelled {
			// The common attributes are always packed; a directory's entry carries only the
			// directory group and anything else's only the file group.
			let count = getattrlistbulk(directory, &attributes, buffer, Self.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
			guard count > 0 else { break }
			var entry = buffer
			for _ in 0 ..< count {
				let length = entry.loadUnaligned(as: UInt32.self)
				let returned = entry.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
				let nameReference = entry + 4 + MemoryLayout<attribute_set_t>.size
				let objectType = nameReference.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
				let fileID = nameReference.loadUnaligned(fromByteOffset: 12, as: UInt64.self)
				let groupAttributes = nameReference + 20

				if objectType == VDIR.rawValue {
					let mountStatus = groupAttributes.loadUnaligned(as: UInt32.self)
					if returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0,
					   mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) == 0 {
						let nameOffset = Int(nameReference.loadUnaligned(as: Int32.self))
						subdirectoryNames.append(String(cString: (nameReference + nameOffset).assumingMemoryBound(to: CChar.self)))
					}
				}
				else if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
					let linkCount = groupAttributes.loadUnaligned(as: UInt32.self)
					let allocatedSize = groupAttributes.loadUnaligned(fromByteOffset: 4, as: Int64.self)
					if linkCount <= 1 || hardLinksSeen.insert(fileID).inserted {
						total += allocatedSize
					}
				}

				entriesRead += 1
				if entriesRead.isMultiple(of: 4096), Task.isCancelled {
					isCancelled = true
				}
				entry += Int(length)
			}
		}

		for name in subdirectoryNames where !isCancelled {
			let subdirectory = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			if subdirectory >= 0 {
				add(directory: subdirectory)
			}
		}
	}
}
