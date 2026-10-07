import ComposableArchitecture
import Foundation

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	/// Base URL of the Homer instance the console talks to, as normalized by
	/// `HomerEndpoint.normalize`. Empty until the first sign-in.
	static var homerBaseURL: Self {
		appStorage("homerBaseURL")
	}
}

public nonisolated enum HomerEndpointError: Error, Equatable, LocalizedError {
	case empty
	case invalid
	case unsupportedScheme

	public var errorDescription: String? {
		switch self {
		case .empty:
			"Enter the Homer instance URL."
		case .invalid:
			"That is not a valid URL."
		case .unsupportedScheme:
			"The instance URL must start with https:// or http://."
		}
	}
}

public nonisolated enum HomerEndpoint {
	/// The console's own page routes. A URL copied from the browser's address bar ends in one of
	/// these, and the API lives at the part before it.
	private static let consoleRoutes: Set<String> = [
		"processes", "questions", "continuations", "schedules", "agents", "costs", "runners", "login",
	]

	/// Turns what the user typed into the instance's base URL: `https` is assumed when no scheme
	/// is given, a trailing console page (`/processes/123`, `/questions`) is dropped along with
	/// any query or fragment, and no trailing slash is kept — API paths are appended to it.
	/// Unlike the web console's `normalizeBaseUrl` this accepts a pasted page URL, because the
	/// address bar is where a user finds it.
	public static func normalize(_ raw: String) throws(HomerEndpointError) -> String {
		var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw .empty
		}
		if !trimmed.contains("://") {
			trimmed = "https://" + trimmed
		}
		guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else {
			throw .invalid
		}
		guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
			throw .unsupportedScheme
		}
		components.scheme = scheme
		components.query = nil
		components.fragment = nil

		var segments = components.path.split(separator: "/").map(String.init)
		if let routeIndex = segments.firstIndex(where: { consoleRoutes.contains($0) }) {
			segments.removeSubrange(routeIndex...)
		}
		components.path = segments.isEmpty ? "" : "/" + segments.joined(separator: "/")

		guard let normalized = components.string else {
			throw .invalid
		}
		return normalized
	}

	/// The host shown for an instance, e.g. in the console's header.
	public static func displayName(of baseURL: String) -> String {
		URLComponents(string: baseURL)?.host ?? baseURL
	}

	/// A page of the web console, e.g. `processes/42`.
	public static func pageURL(baseURL: String, path: String) -> URL? {
		URL(string: baseURL + "/" + path)
	}
}
