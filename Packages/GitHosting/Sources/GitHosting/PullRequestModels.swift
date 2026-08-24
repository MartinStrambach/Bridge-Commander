import Foundation

public nonisolated enum PullRequestProvider: String, Sendable, Equatable {
	case github
	case gitlab
}

public nonisolated enum PullRequestState: String, Sendable, Equatable {
	case draft
	case ready
	case merged
	case closed

	/// Whether the MR/PR is still open for review. Merged/closed ones skip follow-up
	/// queries like the unresolved discussion count.
	public var isOpen: Bool {
		self == .draft || self == .ready
	}
}

public nonisolated enum PipelineState: String, Sendable, Equatable {
	case created
	case waitingForResource
	case preparing
	case pending
	case running
	case success
	case failed
	case canceled
	case skipped
	case manual
	case scheduled

	/// Maps a raw GitLab pipeline `status` string to a `PipelineState`.
	/// Unrecognized statuses return `nil` so no badge is shown for unknown future values.
	public init?(gitLabStatus: String) {
		switch gitLabStatus {
		case "created": self = .created
		case "waiting_for_resource": self = .waitingForResource
		case "preparing": self = .preparing
		case "pending": self = .pending
		case "running": self = .running
		case "success": self = .success
		case "failed": self = .failed
		case "canceled": self = .canceled
		case "skipped": self = .skipped
		case "manual": self = .manual
		case "scheduled": self = .scheduled
		default: return nil
		}
	}

	/// SF Symbol name for the status icon. Lives here (no SwiftUI) so it is unit-testable.
	public var systemImageName: String {
		switch self {
		case .success: "checkmark.circle.fill"
		case .failed: "xmark.octagon.fill"
		case .running: "arrow.triangle.2.circlepath"
		case .pending, .created, .preparing, .waitingForResource, .scheduled: "clock"
		case .canceled: "stop.circle"
		case .skipped: "forward.end.circle"
		case .manual: "hand.tap"
		}
	}
}

public nonisolated struct PipelineStatus: Equatable, Sendable {
	public let state: PipelineState
	public let url: String

	public init(state: PipelineState, url: String) {
		self.state = state
		self.url = url
	}
}

public nonisolated struct PullRequestDetails: Equatable, Sendable {
	public let url: String
	public let state: PullRequestState
	public let provider: PullRequestProvider
	public let pipeline: PipelineStatus?
	/// Number of unresolved review discussions (GitLab) / review threads (GitHub).
	/// `nil` when the count could not be determined, so the UI can tell "0" from "unknown".
	public let unresolvedDiscussionsCount: Int?

	public init(
		url: String,
		state: PullRequestState,
		provider: PullRequestProvider,
		pipeline: PipelineStatus? = nil,
		unresolvedDiscussionsCount: Int? = nil
	) {
		self.url = url
		self.state = state
		self.provider = provider
		self.pipeline = pipeline
		self.unresolvedDiscussionsCount = unresolvedDiscussionsCount
	}
}
