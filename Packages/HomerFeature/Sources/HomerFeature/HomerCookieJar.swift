import Foundation
import Synchronization

/// Each instance's session cookies, kept apart from one another. `HTTPCookieStorage` matches
/// cookies by host alone — not by port, and Homer's `homer_session` has `Path=/` — so two
/// instances on one host (`localhost:8080` and `localhost:8081`, or two sub-paths) would sign
/// each other out there. Here every instance has its own jar, keyed by its base URL, and every
/// cookie in it goes with every call to that instance.
///
/// The jars are persisted (`homerSessions.json` in Application Support, readable by the user
/// alone), so a session survives a relaunch the way it survives a browser restart — the same
/// trade `HTTPCookieStorage.shared` makes with its own file.
nonisolated final class HomerCookieJar: Sendable {
	static let shared = HomerCookieJar(fileURL: applicationSupportURL(name: "homerSessions.json"))

	private let fileURL: URL?
	private let jars: Mutex<[String: [StoredCookie]]>

	/// `fileURL` nil keeps the jars in memory only.
	init(fileURL: URL?) {
		self.fileURL = fileURL
		let stored = fileURL
			.flatMap { try? Data(contentsOf: $0) }
			.flatMap { try? JSONDecoder().decode([String: [StoredCookie]].self, from: $0) }
		self.jars = Mutex(stored ?? [:])
	}

	/// The instance's cookies that have not expired.
	func cookies(for baseURL: String, now: Date = Date()) -> [HTTPCookie] {
		jars.withLock { jars in
			(jars[baseURL] ?? []).filter { !$0.isExpired(at: now) }.compactMap(\.httpCookie)
		}
	}

	/// Takes in what a response's `Set-Cookie` says: a cookie replaces the one of the same name,
	/// and one that arrives expired (the logout answer's) removes it.
	func update(for baseURL: String, from response: HTTPURLResponse, now: Date = Date()) {
		guard let setCookie = response.value(forHTTPHeaderField: "Set-Cookie"), let url = response.url else {
			return
		}
		let received = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: url)
		guard !received.isEmpty else {
			return
		}
		jars.withLock { jars in
			var jar = jars[baseURL] ?? []
			for cookie in received {
				jar.removeAll { $0.name == cookie.name && $0.path == cookie.path }
				let stored = StoredCookie(cookie)
				if !stored.isExpired(at: now) {
					jar.append(stored)
				}
			}
			jar.removeAll { $0.isExpired(at: now) }
			jars[baseURL] = jar.isEmpty ? nil : jar
			save(jars)
		}
	}

	func removeAll(for baseURL: String) {
		jars.withLock { jars in
			guard jars.removeValue(forKey: baseURL) != nil else {
				return
			}
			save(jars)
		}
	}

	/// Called with the lock held, so writes land in the order the changes were made.
	private func save(_ jars: [String: [StoredCookie]]) {
		guard let fileURL, let data = try? JSONEncoder().encode(jars) else {
			return
		}
		let fileManager = FileManager.default
		try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		guard (try? data.write(to: fileURL, options: .atomic)) != nil else {
			return
		}
		try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
	}

	/// What an `HTTPCookie` holds that matters here, in a form `Codable` can write.
	private struct StoredCookie: Codable {
		var name: String
		var value: String
		var domain: String
		var path: String
		var expires: Date?
		var isSecure: Bool
		var isHTTPOnly: Bool
		var sameSite: String?

		init(_ cookie: HTTPCookie) {
			name = cookie.name
			value = cookie.value
			domain = cookie.domain
			path = cookie.path
			expires = cookie.expiresDate
			isSecure = cookie.isSecure
			isHTTPOnly = cookie.isHTTPOnly
			sameSite = cookie.sameSitePolicy?.rawValue
		}

		func isExpired(at now: Date) -> Bool {
			expires.map { $0 <= now } ?? false
		}

		var httpCookie: HTTPCookie? {
			var properties: [HTTPCookiePropertyKey: Any] = [
				.name: name,
				.value: value,
				.domain: domain,
				.path: path,
			]
			if let expires {
				properties[.expires] = expires
			}
			if isSecure {
				properties[.secure] = "TRUE"
			}
			if isHTTPOnly {
				// No public constant; this is the key `HTTPCookie` reads `HttpOnly` from.
				properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
			}
			if let sameSite {
				properties[.sameSitePolicy] = sameSite
			}
			return HTTPCookie(properties: properties)
		}
	}
}

private nonisolated func applicationSupportURL(name: String) -> URL {
	let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
	let appSupport = urls.first ?? URL(fileURLWithPath: NSHomeDirectory())
		.appending(component: "Library/Application Support")
	return appSupport
		.appending(component: Bundle.main.bundleIdentifier ?? "BridgeCommander")
		.appending(component: name)
}
