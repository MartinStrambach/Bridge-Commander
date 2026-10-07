import ComposableArchitecture
import CryptoKit
import Foundation

public nonisolated extension SharedReaderKey where Self == AppStorageKey<[String]> {
	/// Base URLs of the Homer instances the console knows, as normalized by
	/// `HomerEndpoint.normalize`, in the order they were added. An instance joins the list on its
	/// first successful sign-in and leaves it only when removed.
	static var homerInstanceURLs: Self {
		appStorage("homerInstanceURLs")
	}
}

public nonisolated extension SharedReaderKey where Self == AppStorageKey<String> {
	/// Base URL of the instance on screen, one of `homerInstanceURLs`.
	static var homerSelectedInstance: Self {
		appStorage("homerSelectedInstance")
	}
}

public nonisolated extension SharedReaderKey where Self == FileStorageKey<[String: String]>.Default {
	/// The username last signed in to each instance, by base URL, so its form is filled after a
	/// relaunch outlived the session. Not a secret; the password is never stored.
	static var homerUsernames: Self {
		Self[.fileStorage(applicationSupportURL(name: "homerUsernames.json")), default: [:]]
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

	/// How an instance is named, e.g. in the header's instance menu: its host, with the port and
	/// sub-path when it has them, so two instances on one host stay apart.
	public static func displayName(of baseURL: String) -> String {
		guard let components = URLComponents(string: baseURL), let host = components.host else {
			return baseURL
		}
		return host + (components.port.map { ":\($0)" } ?? "") + components.path
	}

	/// The embedded web console's `WKWebsiteDataStore` for an instance, derived from its URL so it
	/// stays the same across launches: each instance gets its own store, so their cookies stay
	/// apart there as they do in `HomerCookieJar`.
	public static func webDataStoreID(baseURL: String) -> UUID {
		var bytes = Array(SHA256.hash(data: Data(baseURL.utf8)).prefix(16))
		// A name-based UUID's version and variant bits (RFC 9562).
		bytes[6] = (bytes[6] & 0x0F) | 0x50
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		return bytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
	}

	/// A page of the web console, e.g. `processes/42`.
	public static func pageURL(baseURL: String, path: String) -> URL? {
		URL(string: baseURL + "/" + path)
	}
}
