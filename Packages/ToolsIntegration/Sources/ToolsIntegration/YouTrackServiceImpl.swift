import Dependencies
import DependenciesMacros
import Foundation
import Settings
import Sharing

// MARK: - YouTrack Service

@DependencyClient
public struct YouTrackClient: Sendable {
	public var fetchIssueDetails: @Sendable (_ for: String) async throws -> IssueDetails
}

extension YouTrackClient: DependencyKey {
	public static let liveValue = YouTrackClient(
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
	public static let testValue = YouTrackClient()
}
