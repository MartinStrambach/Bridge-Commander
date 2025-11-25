import Foundation

// MARK: - YouTrack Service

struct YouTrackServiceImpl: YouTrackServiceType, Sendable {

	func extractTicketId(from branch: String) -> String? {
		GitBranchDetector.extractTicketId(from: branch)
	}

	func fetchIssueDetails(for ticketId: String) async throws -> IssueDetails {
		let (prUrl, androidCR, iosCR, androidReviewerName, iosReviewerName) = await YouTrackService
			.fetchIssueDetails(for: ticketId)

		return IssueDetails(
			prUrl: prUrl,
			androidCR: androidCR,
			iosCR: iosCR,
			androidReviewerName: androidReviewerName,
			iosReviewerName: iosReviewerName
		)
	}
}
