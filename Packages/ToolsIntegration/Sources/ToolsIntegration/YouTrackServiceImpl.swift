import Dependencies
import DependenciesMacros
import Foundation

// MARK: - YouTrack Service

@DependencyClient
public struct YouTrackClient: Sendable {
	public var fetchIssueDetails: @Sendable (_ for: String, _ authToken: String) async throws -> IssueDetails
	public var applyStateEvent: @Sendable (
		_ for: String,
		_ fieldId: String,
		_ eventId: String,
		_ authToken: String
	) async throws -> Void
}

extension YouTrackClient: DependencyKey {
	public static let liveValue = YouTrackClient(
		fetchIssueDetails: { ticketId, authToken in
			try await YouTrackService.fetchIssueDetails(for: ticketId, authToken: authToken)
		},
		applyStateEvent: { ticketId, fieldId, eventId, authToken in
			try await YouTrackService.applyStateEvent(
				for: ticketId,
				fieldId: fieldId,
				eventId: eventId,
				authToken: authToken
			)
		}
	)
}

extension YouTrackClient: TestDependencyKey {
	public static let testValue = YouTrackClient()
}
