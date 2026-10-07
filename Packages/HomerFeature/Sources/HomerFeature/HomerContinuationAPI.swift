import Foundation

/// The Continuations page's calls (`getContinuations`/`cancelContinuation` in the console's
/// `lib/api/client.ts`). The server lists only the continuations the user may see.
extension HomerAPI {
	static func continuations(baseURL: String, status: HomerContinuationStatus) async throws -> [HomerContinuation] {
		let data = try await send(
			"GET",
			"/api/v1/continuations",
			baseURL: baseURL,
			queryItems: [URLQueryItem(name: "status", value: status.rawValue)]
		)
		return try decode(HomerContinuationList.self, from: data).continuations
	}

	/// Answers 409 when the continuation is no longer pending, 404 when it is gone or not the
	/// user's to control.
	static func cancelContinuation(baseURL: String, id: Int) async throws {
		_ = try await send("DELETE", "/api/v1/continuations/\(id)", baseURL: baseURL)
	}
}
