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

	public var tallies: [Kind: Tally]
	public var measuredFolders: Int
	public var totalFolders: Int

	public init(tallies: [Kind: Tally] = [:], measuredFolders: Int = 0, totalFolders: Int = 0) {
		self.tallies = tallies
		self.measuredFolders = measuredFolders
		self.totalFolders = totalFolders
	}

	public var isComplete: Bool { measuredFolders == totalFolders }
	public var totalBytes: Int64 { tallies.values.reduce(0) { $0 + $1.bytes } }

	public subscript(kind: Kind) -> Tally {
		tallies[kind] ?? Tally()
	}
}

/// What deleting one kind of DerivedData folder did.
public struct DerivedDataDeletion: Equatable, Sendable {
	public var deletedFolders: Int
	/// One description per folder that could not be removed.
	public var failures: [String]

	public init(deletedFolders: Int = 0, failures: [String] = []) {
		self.deletedFolders = deletedFolders
		self.failures = failures
	}
}

public nonisolated enum DerivedDataUsageScanner {

	/// Folders measured at once. On a 174 GB DerivedData folder, four took 14 s where `du -sk`
	/// took 53 s, with the same total (checked 2026-10-15).
	private static let concurrentMeasurements = 4

	/// Classifies every DerivedData folder, then measures them, yielding the usage after each.
	public static func measure(in derivedDataURL: URL = defaultDerivedDataURL) -> AsyncStream<DerivedDataUsage> {
		AsyncStream { continuation in
			let task = Task {
				let folders = classifyFolders(in: derivedDataURL)
				var usage = DerivedDataUsage(totalFolders: folders.count)
				for folder in folders {
					usage.tallies[folder.kind, default: .init()].folders += 1
				}
				continuation.yield(usage)

				await withTaskGroup(of: (DerivedDataUsage.Kind, Int64).self) { group in
					var pending = folders.makeIterator()
					func addNext() {
						guard let folder = pending.next() else { return }
						group.addTask { (folder.kind, allocatedBytes(at: folder.url)) }
					}
					for _ in 0 ..< concurrentMeasurements {
						addNext()
					}
					for await (kind, bytes) in group {
						usage.tallies[kind, default: .init()].bytes += bytes
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

	/// Deletes every folder of a deletable kind. The folders are classified again here rather
	/// than taken from the last measurement, so a folder whose workspace has reappeared since
	/// (a worktree recreated at the same path) is kept.
	public static func deleteFolders(
		of kind: DerivedDataUsage.Kind,
		in derivedDataURL: URL = defaultDerivedDataURL
	) -> DerivedDataDeletion {
		guard deletableKinds.contains(kind) else {
			return DerivedDataDeletion()
		}
		var deletion = DerivedDataDeletion()
		for folder in classifyFolders(in: derivedDataURL) where folder.kind == kind {
			do {
				try XcodeDerivedDataHelper.removeFolder(at: folder.url)
				deletion.deletedFolders += 1
			}
			catch {
				deletion.failures.append(error.localizedDescription)
			}
		}
		return deletion
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
	/// hard-linked file once, symbolic links not followed. Stops early when the task is cancelled.
	static func allocatedBytes(at url: URL) -> Int64 {
		guard let path = strdup(url.path(percentEncoded: false)) else {
			return 0
		}
		defer { free(path) }
		var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
		guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
			return 0
		}
		defer { fts_close(fts) }

		struct Inode: Hashable {
			let device: dev_t
			let number: ino_t
		}
		var hardLinksSeen = Set<Inode>()
		var total: Int64 = 0
		var visited = 0
		while let entry = fts_read(fts) {
			visited += 1
			if visited.isMultiple(of: 4096), Task.isCancelled {
				break
			}
			switch Int32(entry.pointee.fts_info) {
			case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_DP:
				guard let stat = entry.pointee.fts_statp?.pointee else { continue }
				if stat.st_nlink > 1, (stat.st_mode & S_IFMT) != S_IFDIR,
				   !hardLinksSeen.insert(Inode(device: stat.st_dev, number: stat.st_ino)).inserted {
					continue
				}
				total += Int64(stat.st_blocks) * 512
			default:
				continue
			}
		}
		return total
	}
}
