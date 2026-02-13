import Dependencies
import DependenciesMacros
import Foundation
import Sharing

// MARK: - YouTrack Service

@DependencyClient
nonisolated struct YouTrackClient: Sendable {
	var fetchIssueDetails: @Sendable (_ for: String) async throws -> IssueDetails
}

extension YouTrackClient: DependencyKey {
	static let liveValue = YouTrackClient(
		fetchIssueDetails: { ticketId in
			@Shared(.youtrackAuthToken)
			var token = ""

			let (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState) = await YouTrackService
				.fetchIssueDetails(for: ticketId, authToken: token)

			return IssueDetails(
				prUrl: prUrl,
				androidCR: androidCR,
				iosCR: iosCR,
				androidReviewerName: androidReviewerName,
				iosReviewerName: iosReviewerName,
				ticketState: ticketState
			)
		}
	)
}

extension YouTrackClient: TestDependencyKey {
	static let testValue = YouTrackClient()
}
