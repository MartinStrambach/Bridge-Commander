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

	/// How many pending continuations the user may see — the console's sidebar badge
	/// (`usePendingContinuationsCount`). `total` counts past the page, so one row is enough.
	static func pendingContinuationCount(baseURL: String) async throws -> Int {
		let data = try await send(
			"GET",
			"/api/v1/continuations",
			baseURL: baseURL,
			queryItems: [
				URLQueryItem(name: "status", value: HomerContinuationStatus.pending.rawValue),
				URLQueryItem(name: "limit", value: "1"),
			]
		)
		let list = try decode(HomerContinuationList.self, from: data)
		return list.total ?? list.continuations.count
	}

	/// Answers 409 when the continuation is no longer pending, 404 when it is gone or not the
	/// user's to control.
	static func cancelContinuation(baseURL: String, id: Int) async throws {
		_ = try await send("DELETE", "/api/v1/continuations/\(id)", baseURL: baseURL)
	}
}
