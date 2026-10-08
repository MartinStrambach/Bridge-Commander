import Foundation

public nonisolated extension URLSession {
	/// `data(for:)`, recorded in the activity log: method, URL, status code and duration, plus the
	/// start of the body when the status is not 2xx. Headers and request bodies are never
	/// recorded — they carry the tokens.
	func loggedData(for request: URLRequest) async throws -> (Data, URLResponse) {
		let start = ContinuousClock.now
		let summary = NetworkRequestLog.summary(of: request)
		do {
			let (data, response) = try await data(for: request)
			let elapsed = ContinuousClock.now - start
			let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
			let isSuccess = (200 ..< 300).contains(statusCode)
			ActivityLog.shared.record(
				isSuccess ? .network : .error,
				"\(summary) → \(statusCode) in \(elapsed.activityLogDescription)",
				details: isSuccess ? nil : NetworkRequestLog.bodyExcerpt(data)
			)
			return (data, response)
		}
		catch {
			if !ActivityLog.isCancellation(error) {
				ActivityLog.shared.record(
					.error,
					"\(summary) → failed in \((ContinuousClock.now - start).activityLogDescription): \(ActivityLog.describe(error))"
				)
			}
			throw error
		}
	}
}

nonisolated enum NetworkRequestLog {
	/// Query items whose values are dropped from a logged URL, in case a token ever rides in one.
	private static let secretQueryNames: Set<String> = ["token", "access_token", "private_token", "api_key", "key"]
	private static let maximumBodyExcerpt = 1000

	static func summary(of request: URLRequest) -> String {
		"\(request.httpMethod ?? "GET") \(request.url.map(redacted) ?? "<no URL>")"
	}

	static func redacted(_ url: URL) -> String {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url.absoluteString
		}

		components.user = nil
		components.password = nil
		components.queryItems = components.queryItems?.map { item in
			secretQueryNames.contains(item.name.lowercased())
				? URLQueryItem(name: item.name, value: "<redacted>")
				: item
		}
		return components.string ?? url.absoluteString
	}

	static func bodyExcerpt(_ data: Data) -> String? {
		guard !data.isEmpty else {
			return nil
		}

		let text = String(decoding: data.prefix(maximumBodyExcerpt), as: UTF8.self)
		return data.count > maximumBodyExcerpt ? text + "… (\(data.count) bytes)" : text
	}
}

public nonisolated extension Duration {
	/// `840 ms` or `2.31 s`, as the activity log writes how long something took — in the same
	/// notation whatever the locale, since the log is read by whoever it is shared with.
	var activityLogDescription: String {
		let milliseconds = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
		return milliseconds < 1000
			? "\(milliseconds) ms"
			: (Double(milliseconds) / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX"))) + " s"
	}
}
