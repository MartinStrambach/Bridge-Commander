import Foundation

// MARK: - Git Service Protocol

protocol GitServiceType: Sendable {
	func getCurrentBranch(at path: String) async
		-> (branch: String, unstagedCount: Int, stagedCount: Int)
	func countUnpushedCommits(at path: String) async throws -> Int
	func mergeMaster(at path: String) async throws
	func pull(at path: String) async throws -> GitPullHelper.PullResult
}

// MARK: - YouTrack Service Protocol

protocol YouTrackServiceType: Sendable {
	func extractTicketId(from branch: String) -> String?
	func fetchIssueDetails(for ticketId: String) async throws -> IssueDetails
}

struct IssueDetails: Sendable {
	let prUrl: String?
	let androidCR: String?
	let iosCR: String?
	let androidReviewerName: String?
	let iosReviewerName: String?
}

// MARK: - Xcode Service Protocol

protocol XcodeServiceType: Sendable {
	func hasXcodeProject(in path: String) -> Bool
	func findXcodeProject(in repositoryPath: String) -> String?
}

// MARK: - Last Opened Directory Service Protocol

protocol LastOpenedDirectoryServiceType: Sendable {
	func load() -> String?
	func save(_ directory: String)
	func clear()
}
