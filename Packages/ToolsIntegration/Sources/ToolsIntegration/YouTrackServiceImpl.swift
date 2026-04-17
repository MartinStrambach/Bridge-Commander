import Dependencies
import DependenciesMacros
import Foundation

// MARK: - YouTrack Service

@DependencyClient
public struct YouTrackClient: Sendable {
	public var fetchIssueDetails: @Sendable (_ for: String, _ authToken: String) async throws -> IssueDetails
}

extension YouTrackClient: DependencyKey {
	public static let liveValue = YouTrackClient(
		fetchIssueDetails: { ticketId, authToken in
			let (androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState) = await YouTrackService
				.fetchIssueDetails(for: ticketId, authToken: authToken)

			return IssueDetails(
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
