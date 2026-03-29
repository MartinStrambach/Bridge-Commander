import Dependencies
import Foundation

// MARK: - YouTrack Service Protocol

public nonisolated enum CodeReviewState: String, Equatable {
	case passed = "Passed"
	case waiting = "Waiting"
	case notApplicable = "N/A"

	public init?(rawValue: String) {
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

public nonisolated enum TicketState: String, Equatable {
	case open = "Open"
	case inProgress = "In Progress"
	case waitingToCodeReview = "Waiting to code review"
	case waitingForTesting = "Waiting for testing"
	case waitingToAcceptation = "Waiting to acceptation"
	case accepted = "Accepted"
	case done = "Done"

	public init?(rawValue: String) {
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

public protocol YouTrackServiceType: Sendable {
	func fetchIssueDetails(for ticketId: String, authToken: String) async throws -> IssueDetails
}

public struct IssueDetails {
	public let prUrl: String?
	public let androidCR: CodeReviewState?
	public let iosCR: CodeReviewState?
	public let androidReviewerName: String?
	public let iosReviewerName: String?
	public let ticketState: TicketState?

	public init(prUrl: String?, androidCR: CodeReviewState?, iosCR: CodeReviewState?, androidReviewerName: String?, iosReviewerName: String?, ticketState: TicketState?) {
		self.prUrl = prUrl
		self.androidCR = androidCR
		self.iosCR = iosCR
		self.androidReviewerName = androidReviewerName
		self.iosReviewerName = iosReviewerName
		self.ticketState = ticketState
	}
}

// MARK: - Xcode Service Protocol

public nonisolated protocol XcodeServiceType: Sendable {
	func hasXcodeProject(in path: String, iosSubfolderPath: String) -> Bool
	func findXcodeProject(in repositoryPath: String, iosSubfolderPath: String) -> String?
}

// MARK: - Last Opened Directory Service Protocol

public protocol LastOpenedDirectoryServiceType: Sendable {
	func load() -> String?
	func save(_ directory: String)
	func clear()
}
