import Foundation

/// Builds YouTrack URLs from a user-configured base URL.
///
/// The base is the instance origin, optionally with a path for path-hosted instances
/// (`https://org.youtrack.cloud`, `https://org.myjetbrains.com/youtrack`). An empty base
/// means the YouTrack integration is disabled. Normalization happens here rather than when
/// the setting is stored, because the settings field binds per keystroke — stripping a
/// trailing `/` on write would make `https://` untypeable.
public nonisolated enum YouTrackURLBuilder {
	/// Returns the effective base: whitespace-trimmed, without trailing slashes, and without a
	/// trailing `/api` (users pasting the API root would otherwise get `/api/api/...` and
	/// browser links into `/api`).
	public static func normalizedBase(_ raw: String) -> String {
		var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		while base.hasSuffix("/") {
			base.removeLast()
		}
		if base.lowercased().hasSuffix("/api") {
			base.removeLast("/api".count)
		}
		while base.hasSuffix("/") {
			base.removeLast()
		}
		return base
	}

	/// The browser URL of a ticket, or nil when no base URL is configured.
	public static func issueURL(baseURL: String, ticketId: String) -> String? {
		let base = normalizedBase(baseURL)
		guard !base.isEmpty else {
			return nil
		}
		return "\(base)/issue/\(ticketId)"
	}
}
