import Foundation

nonisolated enum XcodeDerivedDataHelper {

	/// Deletes Xcode DerivedData folders associated with the given worktree path.
	/// - Parameter path: The path of the worktree whose DerivedData should be removed.
	/// - Throws: An error if any matching DerivedData folder cannot be removed.
	static func deleteDerivedData(forWorktreePath path: String) throws {
		let derivedDataURL = FileManager.default
			.homeDirectoryForCurrentUser
			.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)

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

			if workspacePath.hasPrefix(path) {
				try FileManager.default.removeItem(at: folderURL)
			}
		}
	}
}
