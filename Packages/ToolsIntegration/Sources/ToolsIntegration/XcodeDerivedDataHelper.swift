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
				try FileManager.default.removeItem(at: folderURL)
			}
		}
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
