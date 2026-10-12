import Foundation
import SimulatorFeature

/// `path` as it reads after the folder `oldPath` was renamed or moved to `newPath`: the folder
/// itself, or anything inside it, follows; any other path is returned unchanged.
func relocatedPath(_ path: String, from oldPath: String, to newPath: String) -> String {
	if path == oldPath {
		return newPath
	}
	guard path.hasPrefix(oldPath + "/") else {
		return path
	}
	return newPath + path.dropFirst(oldPath.count)
}

extension TerminalLayoutReducer.State {
	/// Follows a repository folder renamed or moved from `oldPath` to `newPath`: the repository on
	/// screen, the tab remembered per repository and the simulator pane's repository are all
	/// known by path.
	mutating func relocate(from oldPath: String, to newPath: String) {
		activeRepositoryPath = activeRepositoryPath.map { relocatedPath($0, from: oldPath, to: newPath) }
		tabMemory.relocate(from: oldPath, to: newPath)
		simulatorPane.repositoryPath = simulatorPane.repositoryPath.map {
			relocatedPath($0, from: oldPath, to: newPath)
		}
	}
}

extension TerminalLayoutReducer.State.TabMemory {
	mutating func relocate(from oldPath: String, to newPath: String) {
		lastActiveSessionByRepo = Dictionary(
			lastActiveSessionByRepo.map { (relocatedPath($0.key, from: oldPath, to: newPath), $0.value) },
			uniquingKeysWith: { first, _ in first }
		)
	}
}
