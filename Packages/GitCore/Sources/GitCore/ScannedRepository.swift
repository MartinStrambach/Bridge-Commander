import Foundation

// MARK: - Scanned Repository

public struct ScannedRepository: Equatable, Sendable {
	public var path: String
	public var name: String
	public var directory: String
	public var isWorktree: Bool
	public var branchName: String?

	public init(path: String, name: String, directory: String, isWorktree: Bool, branchName: String? = nil) {
		self.path = path
		self.name = name
		self.directory = directory
		self.isWorktree = isWorktree
		self.branchName = branchName
	}
}
