import Foundation

public nonisolated extension YouTrackService {
	/// Checks a token against one YouTrack instance by asking who it authenticates as.
	/// - Returns: the login the token resolves to, or the display name when YouTrack reports no login.
	/// - Throws: when the token or base URL is missing, the URL is malformed, YouTrack answers with
	/// anything but 200, or the answer is not a YouTrack user (``YouTrackServiceError/unexpectedResponse``
	/// — typically a base URL that points at some other web page, which still answers 200).
	static func verifyToken(baseURL: String, authToken: String) async throws -> String {
		guard !authToken.isEmpty else {
			throw YouTrackServiceError.missingToken
		}
		let base = YouTrackURLBuilder.normalizedBase(baseURL)
		guard !base.isEmpty else {
			throw YouTrackServiceError.missingBaseURL
		}
		guard let url = URL(string: "\(base)/api/users/me?fields=login,name") else {
			throw YouTrackServiceError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"
		request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
			throw YouTrackServiceError.httpFailure(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
		}
		return try parseCurrentUser(from: data)
	}

	/// Internal so the response mapping is unit-testable from fixture JSON.
	internal static func parseCurrentUser(from data: Data) throws -> String {
		guard let user = try? JSONDecoder().decode(CurrentUser.self, from: data) else {
			throw YouTrackServiceError.unexpectedResponse
		}
		if let login = user.login, !login.isEmpty {
			return login
		}
		if let name = user.name, !name.isEmpty {
			return name
		}
		throw YouTrackServiceError.unexpectedResponse
	}
}

private nonisolated struct CurrentUser: Decodable {
	let login: String?
	let name: String?
}
