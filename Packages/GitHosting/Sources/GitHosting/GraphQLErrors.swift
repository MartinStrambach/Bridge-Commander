import Foundation

/// The `errors` a GraphQL answer carries beside its data, which is then partial or null. They
/// are where a host says why a 200 holds no repository, project or user.
/// Internal (not private) so the reading is unit-testable from fixture JSON.
nonisolated struct GraphQLErrorList: Decodable {
	struct Entry: Decodable {
		/// GitHub's classification (`NOT_FOUND`, `FORBIDDEN`, `INSUFFICIENT_SCOPES`, …); GitLab
		/// sends none.
		let type: String?
		let message: String?
	}

	/// Long enough for GitHub's policy messages, which end in a link to the token's page.
	static let reasonLimit = 400

	let errors: [Entry]?

	/// The first error that says more than "not found": GitHub answers `NOT_FOUND` for every
	/// repository a token cannot see, whatever keeps it from seeing it. Nil for a body without
	/// errors, or of another shape.
	static func explanation(in data: Data) -> String? {
		firstReason(in: data) { $0.type != "NOT_FOUND" }
	}

	/// The first `FORBIDDEN` error: a host refusing the token, as opposed to not finding what was
	/// asked for or the token lacking a scope the question itself needs.
	static func refusal(in data: Data) -> String? {
		firstReason(in: data) { $0.type == "FORBIDDEN" }
	}

	private static func firstReason(in data: Data, where matches: (Entry) -> Bool) -> String? {
		let errors = (try? JSONDecoder().decode(GraphQLErrorList.self, from: data))?.errors ?? []
		return errors.lazy.filter(matches).compactMap(\.reason).first
	}
}

extension GraphQLErrorList.Entry {
	/// The message on one line and within `reasonLimit`, as it is shown in a tooltip and written
	/// to the activity log. Nil for an error without text.
	var reason: String? {
		let words = (message ?? "").split(whereSeparator: \.isWhitespace)
		guard !words.isEmpty else {
			return nil
		}
		let line = words.joined(separator: " ")
		let limit = GraphQLErrorList.reasonLimit
		return line.count > limit ? String(line.prefix(limit)) + "…" : line
	}
}
