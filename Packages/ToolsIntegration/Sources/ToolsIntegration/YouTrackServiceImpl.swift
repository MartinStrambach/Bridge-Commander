import Dependencies
import DependenciesMacros
import Foundation

// MARK: - YouTrack Service

@DependencyClient
public struct YouTrackClient: Sendable {
	public var fetchIssueDetails: @Sendable (
		_ for: String,
		_ baseURL: String,
		_ authToken: String
	) async throws -> IssueDetails
	public var applyStateEvent: @Sendable (
		_ for: String,
		_ fieldId: String,
		_ eventId: String,
		_ baseURL: String,
		_ authToken: String
	) async throws -> Void
	public var searchIssues: @Sendable (
		_ query: String,
		_ baseURL: String,
		_ authToken: String
	) async throws -> [YouTrackIssueSummary]
	/// Returns the login the token authenticates as on the instance at `baseURL`.
	public var verifyToken: @Sendable (
		_ baseURL: String,
		_ authToken: String
	) async throws -> String
}

extension YouTrackClient: DependencyKey {
	public static let liveValue = YouTrackClient(
		fetchIssueDetails: { ticketId, baseURL, authToken in
			try await YouTrackService.fetchIssueDetails(for: ticketId, baseURL: baseURL, authToken: authToken)
		},
		applyStateEvent: { ticketId, fieldId, eventId, baseURL, authToken in
			try await YouTrackService.applyStateEvent(
				for: ticketId,
				fieldId: fieldId,
				eventId: eventId,
				baseURL: baseURL,
				authToken: authToken
			)
		},
		searchIssues: { query, baseURL, authToken in
			try await YouTrackService.searchIssues(query: query, baseURL: baseURL, authToken: authToken)
		},
		verifyToken: { baseURL, authToken in
			try await YouTrackService.verifyToken(baseURL: baseURL, authToken: authToken)
		}
	)
}

extension YouTrackClient: TestDependencyKey {
	public static let testValue = YouTrackClient()
}
