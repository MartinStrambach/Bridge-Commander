import Foundation

public nonisolated enum XcodeDerivedDataHelper {

	/// Deletes Xcode DerivedData folders associated with the given worktree path.
	/// - Parameter path: The path of the worktree whose DerivedData should be removed.
	/// - Throws: An error if any matching DerivedData folder cannot be removed.
	public static func deleteDerivedData(forWorktreePath path: String) throws {
		let derivedDataURL = FileManager.default
			.homeDirectoryForCurrentUser
			.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)

		try deleteDerivedData(forWorktreePath: path, in: derivedDataURL)
	}

	static func deleteDerivedData(forWorktreePath path: String, in derivedDataURL: URL) throws {
		let subfolderURLs = (try? FileManager.default.contentsOfDirectory(
			at: derivedDataURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: .skipsHiddenFiles
		)) ?? []

		for folderURL in subfolderURLs {
			let infoPlistURL = folderURL.appending(path: "info.plist", directoryHint: .notDirectory)
			guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
				continue
			}
			guard
				let data = try? Data(contentsOf: infoPlistURL),
				let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
				let workspacePath = plist["WorkspacePath"] as? String
			else {
				continue
			}

			if isWorkspacePath(workspacePath, inWorktreeAt: path) {
				try removeFolder(at: folderURL)
			}
		}
	}

	/// A refused removal (seen on macOS 27 / Xcode 27, cause not yet pinned down) reports only
	/// the top-level folder, so on failure the folder is first moved to the Trash — a single
	/// rename, which succeeds even when something inside cannot be unlinked — and only if that
	/// fails too is the culprit searched for, so the warning can name the file that blocked it.
	private static func removeFolder(at folderURL: URL) throws {
		let fileManager = FileManager.default
		do {
			try fileManager.removeItem(at: folderURL)
		}
		catch {
			if (try? fileManager.trashItem(at: folderURL, resultingItemURL: nil)) != nil {
				return
			}
			throw DerivedDataRemovalError.removalFailed(
				folderName: folderURL.lastPathComponent,
				blockingItem: firstUnremovableItem(in: folderURL)
			)
		}
	}

	/// Removes the folder's files one at a time and describes the first that cannot be removed.
	private static func firstUnremovableItem(in folderURL: URL) -> String? {
		let fileManager = FileManager.default
		guard let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: nil) else {
			return nil
		}
		for case let itemURL as URL in enumerator {
			var isDirectory: ObjCBool = false
			guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
				continue
			}
			do {
				try fileManager.removeItem(at: itemURL)
			}
			catch {
				let posix = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)
					.map { " (\(String(cString: strerror(Int32($0.code)))))" } ?? ""
				let relativePath = itemURL.path.replacingOccurrences(of: folderURL.path + "/", with: "")
				return relativePath + posix
			}
		}
		return nil
	}

	/// A workspace belongs to the worktree only when it is the worktree directory itself
	/// or lives somewhere inside it. A bare prefix match is not enough: it would also hit
	/// sibling worktrees whose names share a prefix, e.g. "repo-2" when deleting "repo".
	static func isWorkspacePath(_ workspacePath: String, inWorktreeAt worktreePath: String) -> Bool {
		var worktree = worktreePath
		while worktree.count > 1, worktree.hasSuffix("/") {
			worktree.removeLast()
		}
		guard !worktree.isEmpty, worktree != "/" else {
			return false
		}
		return workspacePath == worktree || workspacePath.hasPrefix(worktree + "/")
	}
}

public enum DerivedDataRemovalError: LocalizedError, Equatable {
	case removalFailed(folderName: String, blockingItem: String?)

	public var errorDescription: String? {
		switch self {
		case let .removalFailed(folderName, blockingItem?):
			"“\(folderName)” could not be removed or moved to the Trash; blocked by \(blockingItem)."
		case let .removalFailed(folderName, nil):
			"“\(folderName)” could not be removed or moved to the Trash."
		}
	}
}
