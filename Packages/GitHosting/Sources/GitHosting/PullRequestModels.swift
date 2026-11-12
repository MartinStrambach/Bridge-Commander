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

	/// Whether the pipeline has not finished yet: running, or waiting to start.
	public var isInProgress: Bool {
		switch self {
		case .running, .pending, .created, .preparing, .waitingForResource, .scheduled: true
		case .success, .failed, .canceled, .skipped, .manual: false
		}
	}

	/// Icon for the pipeline badge when the MR's merge state is taken into account:
	/// a passing pipeline on a conflicting MR must not read as "good to go", so it
	/// shows a warning instead of the checkmark. Other states already say "not done".
	/// A merge train pipeline still in progress shows a tram, so it reads differently
	/// from the MR's own pipeline; once finished it shows the usual result icon.
	public func systemImageName(hasConflicts: Bool, isMergeTrain: Bool = false) -> String {
		if isMergeTrain, isInProgress {
			return "tram.fill"
		}
		return hasConflicts && self == .success ? "exclamationmark.triangle.fill" : systemImageName
	}
}

public nonisolated struct PipelineStatus: Equatable, Sendable {
	public let state: PipelineState
	public let url: String
	/// Whether this is a merge train pipeline (GitLab's `mergeRequestEventType` `MERGE_TRAIN`)
	/// rather than one on the MR's source branch or its merged result.
	public let isMergeTrain: Bool

	public init(state: PipelineState, url: String, isMergeTrain: Bool = false) {
		self.state = state
		self.url = url
		self.isMergeTrain = isMergeTrain
	}
}

/// Where an open MR stands with GitLab's merge train.
public nonisolated enum MergeTrainStatus: Equatable, Sendable {
	/// Set to join the train once its own pipeline passes
	/// (auto-merge strategy `ADD_TO_MERGE_TRAIN_WHEN_CHECKS_PASS`).
	case waitingToJoin
	/// On the train. `position` counts from 1 (1 = next to merge); `nil` when GitLab
	/// did not report it.
	case onTrain(position: Int?)

	/// Tooltip text for the pipeline badge.
	public var summary: String {
		switch self {
		case .waitingToJoin:
			"joins the merge train when checks pass"
		case let .onTrain(position?):
			"#\(position) on the merge train"
		case .onTrain(position: nil):
			"on the merge train"
		}
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
	/// Review sign-off state. `nil` when the provider did not report it.
	public let approvals: ApprovalStatus?
	/// Whether the MR/PR conflicts with its base branch. `false` when not reported.
	public let hasConflicts: Bool
	/// Merge train state of an open GitLab MR; `nil` when it is not queued for one.
	public let mergeTrain: MergeTrainStatus?

	public init(
		url: String,
		state: PullRequestState,
		provider: PullRequestProvider,
		pipeline: PipelineStatus? = nil,
		unresolvedDiscussionsCount: Int? = nil,
		approvals: ApprovalStatus? = nil,
		hasConflicts: Bool = false,
		mergeTrain: MergeTrainStatus? = nil
	) {
		self.url = url
		self.state = state
		self.provider = provider
		self.pipeline = pipeline
		self.unresolvedDiscussionsCount = unresolvedDiscussionsCount
		self.approvals = approvals
		self.hasConflicts = hasConflicts
		self.mergeTrain = mergeTrain
	}
}
