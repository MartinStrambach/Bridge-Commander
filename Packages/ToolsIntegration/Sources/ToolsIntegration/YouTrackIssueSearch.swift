import Foundation

/// One hit of a YouTrack issue search: enough to pick a ticket and name a branch after it.
public nonisolated struct YouTrackIssueSummary: Equatable, Sendable, Identifiable {
	/// The human-readable id (`MOB-1963`), which is also what branch names carry.
	public let id: String
	public let summary: String
	public let isResolved: Bool

	public init(id: String, summary: String, isResolved: Bool = false) {
		self.id = id
		self.summary = summary
		self.isResolved = isResolved
	}
}

public nonisolated extension YouTrackService {
	/// What the picker lists before anything is typed: the user's own open work, freshest first.
	static let defaultIssueSearchQuery = "for: me #Unresolved sort by: updated desc"

	/// How many hits one search returns. A picker, not a browser — past this, refine the query.
	static let issueSearchLimit = 50

	/// Runs `query` through YouTrack's own search, so its query language (`for: me`,
	/// `#Unresolved`, `project: MOB`, a bare `MOB-123`) works as it does in the web UI. A blank
	/// query lists ``defaultIssueSearchQuery``.
	/// - Throws: when the token or base URL is missing, the URL is malformed, or YouTrack answers
	/// with anything but 200 (it reports a malformed query as 400).
	static func searchIssues(
		query: String,
		baseURL: String,
		authToken: String
	) async throws -> [YouTrackIssueSummary] {
		guard !authToken.isEmpty else {
			throw YouTrackServiceError.missingToken
		}
		let base = YouTrackURLBuilder.normalizedBase(baseURL)
		guard !base.isEmpty else {
			throw YouTrackServiceError.missingBaseURL
		}
		guard let request = issueSearchRequest(query: query, base: base, authToken: authToken) else {
			throw YouTrackServiceError.invalidURL
		}

		print("YouTrackService: Searching issues: \(request.url?.absoluteString ?? "")")
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw YouTrackServiceError.httpFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
		}
		return try parseIssueSearch(from: data)
	}

	/// Internal so the query encoding is unit-testable without a round trip.
	internal static func issueSearchRequest(query: String, base: String, authToken: String) -> URLRequest? {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard var components = URLComponents(string: "\(base)/api/issues") else {
			return nil
		}
		components.queryItems = [
			URLQueryItem(name: "query", value: trimmed.isEmpty ? defaultIssueSearchQuery : trimmed),
			URLQueryItem(name: "fields", value: "idReadable,summary,resolved"),
			URLQueryItem(name: "$top", value: String(issueSearchLimit)),
		]
		// URLComponents leaves "+" alone in a query, and servers read a bare "+" as a space.
		components.percentEncodedQuery = components.percentEncodedQuery?
			.replacingOccurrences(of: "+", with: "%2B")
		guard let url = components.url else {
			return nil
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		return request
	}

	/// Decodes a search response. Hits without a readable id are dropped — there is nothing to
	/// name a branch after.
	static func parseIssueSearch(from data: Data) throws -> [YouTrackIssueSummary] {
		try JSONDecoder().decode([SearchHit].self, from: data).compactMap { hit in
			guard let id = hit.idReadable, !id.isEmpty else {
				return nil
			}
			return YouTrackIssueSummary(id: id, summary: hit.summary ?? "", isResolved: hit.resolved != nil)
		}
	}
}

/// `resolved` is the resolution timestamp, null while the issue is open.
private nonisolated struct SearchHit: Decodable {
	let idReadable: String?
	let summary: String?
	let resolved: Int64?
}
