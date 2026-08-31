import Dependencies
import Foundation

// MARK: - YouTrack Service Protocol

public nonisolated enum CodeReviewState: String, Equatable, Sendable {
	case passed = "Passed"
	case waiting = "Waiting"
	case inProgress = "In Progress"
	case notApplicable = "N/A"

	public init?(rawValue: String) {
		switch rawValue.lowercased() {
		case "passed":
			self = .passed
		case "waiting":
			self = .waiting
		case "in progress":
			self = .inProgress
		case "n/a":
			self = .notApplicable
		default:
			return nil
		}
	}
}

public nonisolated enum TicketState: String, Equatable, Sendable {
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

/// One transition the YouTrack state machine currently allows out of the issue's state.
///
/// `presentation` is the target state as YouTrack labels it, shown verbatim in the UI so
/// workflow states ``TicketState`` does not model (Duplicate, Invalid, …) still appear.
/// `eventId` is what the API expects back to apply the transition.
public nonisolated struct TicketStateTransition: Equatable, Sendable, Identifiable {
	public let eventId: String
	public let presentation: String

	public var id: String { eventId }

	public init(eventId: String, presentation: String) {
		self.eventId = eventId
		self.presentation = presentation
	}
}

public nonisolated struct IssueDetails: Equatable, Sendable {
	public let androidCR: CodeReviewState?
	public let iosCR: CodeReviewState?
	public let androidReviewerName: String?
	public let iosReviewerName: String?
	public let ticketState: TicketState?
	/// Identifies the issue's State field for writes. Per-project, so it is read back from the
	/// issue rather than hardcoded. Nil when the issue has no State field.
	public let stateFieldId: String?
	/// Empty unless State is governed by a state-machine workflow — without one YouTrack does
	/// not report reachability, and guessing it is worse than offering nothing.
	public let stateTransitions: [TicketStateTransition]

	public init(
		androidCR: CodeReviewState?,
		iosCR: CodeReviewState?,
		androidReviewerName: String?,
		iosReviewerName: String?,
		ticketState: TicketState?,
		stateFieldId: String? = nil,
		stateTransitions: [TicketStateTransition] = []
	) {
		self.androidCR = androidCR
		self.iosCR = iosCR
		self.androidReviewerName = androidReviewerName
		self.iosReviewerName = iosReviewerName
		self.ticketState = ticketState
		self.stateFieldId = stateFieldId
		self.stateTransitions = stateTransitions
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
