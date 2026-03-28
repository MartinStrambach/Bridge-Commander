import Foundation

// MARK: - Scanned Repository

public struct ScannedRepository: Equatable {
	public var path: String
	public var name: String
	public var directory: String
	public var isWorktree: Bool
	public var branchName: String?
	public var isMergeInProgress: Bool

	public init(path: String, name: String, directory: String, isWorktree: Bool, branchName: String? = nil, isMergeInProgress: Bool) {
		self.path = path
		self.name = name
		self.directory = directory
		self.isWorktree = isWorktree
		self.branchName = branchName
		self.isMergeInProgress = isMergeInProgress
	}
}
