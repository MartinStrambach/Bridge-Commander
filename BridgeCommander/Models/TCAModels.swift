import Foundation

// MARK: - Scanned Repository

struct ScannedRepository: Equatable {
	var path: String
	var name: String
	var directory: String
	var isWorktree: Bool
	var branchName: String?
	var isMergeInProgress: Bool
}
