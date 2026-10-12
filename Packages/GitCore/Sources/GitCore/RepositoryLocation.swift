import Dependencies
import DependenciesMacros
import Foundation
import ProcessExecution

// MARK: - Client

/// Finds a tracked repository's folder again after it was renamed or moved on disk.
///
/// The list tracks each repository by its path, and a rename leaves that path naming nothing.
/// A bookmark kept alongside the path still finds the folder: it records the folder's identity,
/// not just its path.
@DependencyClient
public struct RepositoryLocationClient: Sendable {
	/// Where the folder tracked as `path` is now, following `bookmark` when `path` names nothing.
	public var locate: @Sendable (_ path: String, _ bookmark: Data?) -> RepositoryLocation = { _, _ in .missing }
	/// A bookmark to the folder at `path`, or nil when one cannot be made (the folder is gone).
	public var bookmark: @Sendable (_ path: String) -> Data?
	/// Reconnects a repository's linked worktrees after its main folder moved from `oldPath` to
	/// `newPath`; until then their `.git` files point at a folder that no longer exists.
	public var repairWorktreesAfterMove: @Sendable (_ oldPath: String, _ newPath: String) async -> Void
}

/// What `RepositoryLocationClient.locate` found.
public nonisolated enum RepositoryLocation: Equatable, Sendable {
	/// The folder is where it was. `bookmark` is set when the stored one should be replaced: there
	/// was none, or it names a different folder (another one was renamed out of the way and this
	/// one took its name).
	case present(bookmark: Data?)
	/// The folder was renamed or moved to `path`; `bookmark` is a fresh one made there.
	case moved(to: String, bookmark: Data?)
	/// No folder at the path, and no bookmark leading to one outside the Trash.
	case missing
}

extension RepositoryLocationClient: DependencyKey {
	public static var liveValue: RepositoryLocationClient {
		RepositoryLocationClient(
			locate: { path, bookmark in
				RepositoryBookmark.locate(path: path, bookmark: bookmark)
			},
			bookmark: { path in
				RepositoryBookmark.make(path: path)
			},
			repairWorktreesAfterMove: { oldPath, newPath in
				await GitWorktreeRepairer.repairAfterMainMoved(from: oldPath, to: newPath)
			}
		)
	}
}

extension RepositoryLocationClient: TestDependencyKey {
	/// Every folder stays where it is, so a test scanning made-up paths still lists them. Not left
	/// unimplemented: every scan locates its repositories, and most tests that scan are about
	/// something else.
	public static var testValue: RepositoryLocationClient {
		RepositoryLocationClient(
			locate: { _, _ in .present(bookmark: nil) },
			bookmark: { _ in nil },
			repairWorktreesAfterMove: { _, _ in }
		)
	}
}

// MARK: - Bookmarks

nonisolated enum RepositoryBookmark {
	/// What a bookmark records to tell its folder from another one at the same path.
	private static let identityKeys: Set<URLResourceKey> = [.fileIdentifierKey, .volumeIdentifierKey]

	/// A plain bookmark: the app is not sandboxed, so it needs no security scope. It also records
	/// the folder's identity, read back by `isBookmark(_:of:)`.
	static func make(path: String) -> Data? {
		try? URL(fileURLWithPath: path).bookmarkData(
			options: [],
			includingResourceValuesForKeys: identityKeys,
			relativeTo: nil
		)
	}

	/// The folder's current path, or nil when it is gone. A folder moved to the Trash counts as
	/// gone: the bookmark still finds it there, but that is the user getting rid of it.
	static func resolve(_ bookmark: Data) -> String? {
		var isStale = false
		guard
			let url = try? URL(
				resolvingBookmarkData: bookmark,
				options: [.withoutUI, .withoutMounting],
				relativeTo: nil,
				bookmarkDataIsStale: &isStale
			),
			!isInTrash(url.path),
			isDirectory(url.path)
		else {
			return nil
		}

		return url.standardizedFileURL.path
	}

	static func locate(path: String, bookmark: Data?) -> RepositoryLocation {
		if isDirectory(path) {
			let isCurrent = bookmark.map { isBookmark($0, of: path) } ?? false
			return .present(bookmark: isCurrent ? nil : make(path: path))
		}

		guard let current = bookmark.flatMap(resolve) else {
			return .missing
		}

		return .moved(to: current, bookmark: make(path: current))
	}

	/// Whether `path` lies in a Trash: the home folder's `.Trash`, or a volume's `.Trashes`.
	static func isInTrash(_ path: String) -> Bool {
		path.split(separator: "/").contains { $0 == ".Trash" || $0 == ".Trashes" }
	}

	private static func isDirectory(_ path: String) -> Bool {
		var isDirectory: ObjCBool = false
		return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
	}

	/// Whether `bookmark` was made for the folder now at `path`. Not by resolving it: resolution
	/// tries the recorded path first, so it would name whichever folder holds that path now.
	private static func isBookmark(_ bookmark: Data, of path: String) -> Bool {
		guard
			let recorded = URL.resourceValues(forKeys: identityKeys, fromBookmarkData: bookmark),
			let current = try? URL(fileURLWithPath: path).resourceValues(forKeys: identityKeys),
			let recordedFile = recorded.fileIdentifier,
			let recordedVolume = recorded.volumeIdentifier,
			let currentVolume = current.volumeIdentifier
		else {
			return false
		}

		return recordedFile == current.fileIdentifier && recordedVolume.isEqual(currentVolume)
	}
}

// MARK: - Worktree repair

public nonisolated enum GitWorktreeRepairer {
	/// After a main repository's folder moved from `oldPath` to `newPath`, makes its linked
	/// worktrees find it again.
	///
	/// A linked worktree's `.git` file names the main repository's `.git/worktrees/<name>` by
	/// absolute path, and that folder names the worktree back. `git worktree repair` run in the
	/// main repository fixes the first for every worktree it can reach. A worktree that lived
	/// inside the main folder moved with it, so git still lists it at its old path; it is repaired
	/// only when named at its new one. Nothing runs for a repository without linked worktrees.
	public static func repairAfterMainMoved(from oldPath: String, to newPath: String) async {
		let worktrees = await GitWorktreeScanner.listWorktrees(forRepo: newPath)
			.filter(\.isWorktree)
			.map(\.path)
		guard !worktrees.isEmpty else {
			return
		}

		let movedAlong = worktrees.compactMap { path in
			relocated(path, from: oldPath, to: newPath)
		}
		.filter { FileManager.default.fileExists(atPath: $0) }
		_ = await ProcessRunner.runGit(arguments: ["worktree", "repair"] + movedAlong, at: newPath)
	}

	/// `path` as it reads with the folder `oldPath` renamed to `newPath`, or nil when it is not in
	/// that folder. Git reports realpaths, so a temporary folder's `/private` is ignored on either side.
	static func relocated(_ path: String, from oldPath: String, to newPath: String) -> String? {
		let path = withoutPrivatePrefix(path)
		let oldPath = withoutPrivatePrefix(oldPath)
		guard path.hasPrefix(oldPath + "/") else {
			return nil
		}

		return newPath + path.dropFirst(oldPath.count)
	}

	private static func withoutPrivatePrefix(_ path: String) -> String {
		let isPrivate = ["/private/var/", "/private/tmp/", "/private/etc/"].contains { path.hasPrefix($0) }
		return isPrivate ? String(path.dropFirst("/private".count)) : path
	}
}
