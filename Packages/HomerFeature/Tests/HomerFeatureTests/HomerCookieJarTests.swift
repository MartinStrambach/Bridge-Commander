import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer cookie jar")
struct HomerCookieJarTests {
	private static let first = "http://localhost:8080"
	private static let second = "http://localhost:8081"

	private func response(_ baseURL: String, setCookie: String) -> HTTPURLResponse {
		HTTPURLResponse(
			url: URL(string: baseURL + "/api/v1/auth/login")!,
			statusCode: 200,
			httpVersion: nil,
			headerFields: ["Set-Cookie": setCookie]
		)!
	}

	@Test("two instances on one host keep their own sessions, across a relaunch")
	func instancesStayApart() throws {
		let fileURL = FileManager.default.temporaryDirectory
			.appending(component: UUID().uuidString)
			.appending(component: "homerSessions.json")
		defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

		let jar = HomerCookieJar(fileURL: fileURL)
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=one; Path=/; Max-Age=43200; HttpOnly"))
		jar.update(for: Self.second, from: response(Self.second, setCookie: "homer_session=two; Path=/; Max-Age=43200; HttpOnly"))

		let relaunched = HomerCookieJar(fileURL: fileURL)
		#expect(relaunched.cookies(for: Self.first).map(\.value) == ["one"])
		#expect(relaunched.cookies(for: Self.second).map(\.value) == ["two"])
		#expect(relaunched.cookies(for: Self.first).first?.isHTTPOnly == true)

		let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
		#expect(permissions == 0o600)
	}

	@Test("a cookie that arrives expired — the logout answer's — removes the session")
	func expiredCookieRemoves() {
		let jar = HomerCookieJar(fileURL: nil)
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=one; Path=/; Max-Age=43200"))
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=; Path=/; Max-Age=0"))

		#expect(jar.cookies(for: Self.first).isEmpty)
	}

	@Test("a newer cookie of the same name replaces the old one")
	func replacesByName() {
		let jar = HomerCookieJar(fileURL: nil)
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=old; Path=/; Max-Age=43200"))
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=new; Path=/; Max-Age=43200"))

		#expect(jar.cookies(for: Self.first).map(\.value) == ["new"])
	}

	@Test("a cookie past its expiry is no longer sent")
	func expiresWithTime() {
		let jar = HomerCookieJar(fileURL: nil)
		jar.update(for: Self.first, from: response(Self.first, setCookie: "homer_session=one; Path=/; Max-Age=60"))

		#expect(jar.cookies(for: Self.first, now: Date().addingTimeInterval(120)).isEmpty)
	}
}
