import Foundation

// MARK: - Git Service Protocol

protocol GitServiceType: Sendable {
	func getCurrentBranch(at path: String) async
		-> (branch: String, unstagedCount: Int, stagedCount: Int)
	func countUnpushedCommits(at path: String) async throws -> Int
	func countCommitsBehind(at path: String) async throws -> Int
	func mergeMaster(at path: String) async throws
	func pull(at path: String) async throws -> GitPullHelper.PullResult
}

// MARK: - YouTrack Service Protocol

enum CodeReviewState: String, Sendable, Equatable {
	case passed = "Passed"
	case waiting = "Waiting"
	case notApplicable = "N/A"

	init?(rawValue: String) {
		switch rawValue.lowercased() {
		case "passed":
			self = .passed
		case "waiting":
			self = .waiting
		case "n/a":
			self = .notApplicable
		default:
			return nil
		}
	}
}

enum TicketState: String, Sendable, Equatable {
	case open = "Open"
	case inProgress = "In Progress"
	case waitingToCodeReview = "Waiting to code review"
	case waitingForTesting = "Waiting for testing"
	case waitingToAcceptation = "Waiting to acceptation"
	case accepted = "Accepted"
	case done = "Done"

	init?(rawValue: String) {
		switch rawValue.lowercased() {
		case "open":
			self = .open
		case "in progress":
			self = .inProgress
		case "waiting to code review":
			self = .waitingToCodeReview
		case "waiting for testing":
			self = .waitingForTesting
		case "waiting to acceptation":
			self = .waitingToAcceptation
		case "accepted":
			self = .accepted
		case "done":
			self = .done
		default:
			return nil
		}
	}
}

protocol YouTrackServiceType: Sendable {
	func extractTicketId(from branch: String) -> String?
	func fetchIssueDetails(for ticketId: String) async throws -> IssueDetails
}

struct IssueDetails: Sendable {
	let prUrl: String?
	let androidCR: CodeReviewState?
	let iosCR: CodeReviewState?
	let androidReviewerName: String?
	let iosReviewerName: String?
	let ticketState: TicketState?
}

// MARK: - Xcode Service Protocol

protocol XcodeServiceType: Sendable {
	func hasXcodeProject(in path: String, iosSubfolderPath: String) -> Bool
	func findXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> String?
}

// MARK: - Last Opened Directory Service Protocol

protocol LastOpenedDirectoryServiceType: Sendable {
	func load() -> String?
	func save(_ directory: String)
	func clear()
}
