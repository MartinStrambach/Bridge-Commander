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
}

public nonisolated struct PullRequestDetails: Equatable, Sendable {
	public let url: String
	public let state: PullRequestState
	public let provider: PullRequestProvider

	public init(url: String, state: PullRequestState, provider: PullRequestProvider) {
		self.url = url
		self.state = state
		self.provider = provider
	}
}
