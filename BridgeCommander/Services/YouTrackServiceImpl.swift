import ComposableArchitecture
import Foundation

// MARK: - YouTrack Service

struct YouTrackServiceImpl: YouTrackServiceType, Sendable {
	@Dependency(\.authTokenProvider)
	private var authTokenProvider

	func fetchIssueDetails(for ticketId: String) async throws -> IssueDetails {
		let authToken = authTokenProvider.getYouTrackAuthToken()
		let (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName, ticketState) = await YouTrackService
			.fetchIssueDetails(for: ticketId, authToken: authToken)

		return IssueDetails(
			prUrl: prUrl,
			androidCR: androidCR,
			iosCR: iosCR,
			androidReviewerName: androidReviewerName,
			iosReviewerName: iosReviewerName,
			ticketState: ticketState
		)
	}
}
