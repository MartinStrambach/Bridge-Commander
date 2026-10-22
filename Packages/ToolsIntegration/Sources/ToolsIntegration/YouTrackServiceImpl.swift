import ActivityLog
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
	public var listProjects: @Sendable (
		_ baseURL: String,
		_ authToken: String
	) async throws -> [YouTrackProject]
	public var projectFields: @Sendable (
		_ project: YouTrackProject,
		_ baseURL: String,
		_ authToken: String
	) async throws -> YouTrackProjectFields
	public var createIssue: @Sendable (
		_ issue: NewYouTrackIssue,
		_ baseURL: String,
		_ authToken: String
	) async throws -> YouTrackIssueSummary
	/// Sets picked choice values on a filed ticket; returns a line per field that could not be set.
	public var applyFieldValues: @Sendable (
		_ values: [YouTrackFieldValue],
		_ to: String,
		_ baseURL: String,
		_ authToken: String
	) async throws -> [String]
}

extension YouTrackClient: DependencyKey {
	public static let liveValue = YouTrackClient(
		fetchIssueDetails: { ticketId, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack issue \(ticketId)", unless: isNotConfigured) {
				try await YouTrackService.fetchIssueDetails(for: ticketId, baseURL: baseURL, authToken: authToken)
			}
		},
		applyStateEvent: { ticketId, fieldId, eventId, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack event \(eventId) on \(ticketId)") {
				try await YouTrackService.applyStateEvent(
					for: ticketId,
					fieldId: fieldId,
					eventId: eventId,
					baseURL: baseURL,
					authToken: authToken
				)
			}
		},
		searchIssues: { query, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack search", unless: isNotConfigured) {
				try await YouTrackService.searchIssues(query: query, baseURL: baseURL, authToken: authToken)
			}
		},
		verifyToken: { baseURL, authToken in
			try await YouTrackService.verifyToken(baseURL: baseURL, authToken: authToken)
		},
		listProjects: { baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack projects", unless: isNotConfigured) {
				try await YouTrackService.listProjects(baseURL: baseURL, authToken: authToken)
			}
		},
		projectFields: { project, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack project \(project.shortName) fields", unless: isNotConfigured) {
				try await YouTrackService.projectFields(project: project, baseURL: baseURL, authToken: authToken)
			}
		},
		createIssue: { issue, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack new issue in \(issue.projectId)") {
				try await YouTrackService.createIssue(issue, baseURL: baseURL, authToken: authToken)
			}
		},
		applyFieldValues: { values, ticketId, baseURL, authToken in
			try await ActivityLog.shared.recordingErrors("YouTrack fields of \(ticketId)") {
				try await YouTrackService.applyFieldValues(values, to: ticketId, baseURL: baseURL, authToken: authToken)
			}
		}
	)

	/// Rows ask for their ticket on every refresh, so an instance without a token or URL would
	/// fill the log.
	private static func isNotConfigured(_ error: any Error) -> Bool {
		switch error {
		case YouTrackServiceError.missingToken, YouTrackServiceError.missingBaseURL:
			true
		default:
			false
		}
	}
}

extension YouTrackClient: TestDependencyKey {
	public static let testValue = YouTrackClient()
}
