import Foundation
@testable import HomerFeature
import Testing

@Suite("Homer instance URL")
struct HomerEndpointTests {
	@Test(
		"a URL copied from the console's address bar becomes the instance's base URL",
		arguments: [
			("https://mobi-factory-fsmobi.okubefs1.kube.lsoffice.cz/processes", "https://mobi-factory-fsmobi.okubefs1.kube.lsoffice.cz"),
			("https://homer.example.com/processes/123?tab=logs#top", "https://homer.example.com"),
			("https://homer.example.com/questions", "https://homer.example.com"),
			("https://homer.example.com/", "https://homer.example.com"),
			("  https://homer.example.com  ", "https://homer.example.com"),
			("homer.example.com", "https://homer.example.com"),
			("HTTP://localhost:8080/processes", "http://localhost:8080"),
			// A console served under a sub-path keeps it.
			("https://example.com/homer/processes", "https://example.com/homer"),
		]
	)
	func normalizesPastedURL(raw: String, expected: String) throws {
		#expect(try HomerEndpoint.normalize(raw) == expected)
	}

	@Test("an empty field asks for the URL")
	func rejectsEmpty() {
		#expect(throws: HomerEndpointError.empty) {
			try HomerEndpoint.normalize("   ")
		}
	}

	@Test("a non-web scheme is rejected")
	func rejectsOtherSchemes() {
		#expect(throws: HomerEndpointError.unsupportedScheme) {
			try HomerEndpoint.normalize("ftp://homer.example.com")
		}
	}

	@Test("the header names the instance by its host")
	func displayName() {
		#expect(HomerEndpoint.displayName(of: "https://homer.example.com:8443") == "homer.example.com")
	}
}

@Suite("Homer process list query")
struct HomerProcessQueryTests {
	@Test("statuses go out in the console's order, newest first from the top")
	func queryItems() {
		let query = HomerProcessQuery(statuses: [.failed, .working], rootsOnly: true, limit: 100)

		#expect(query.queryItems == [
			URLQueryItem(name: "types", value: "WORKING,FAILED"),
			URLQueryItem(name: "roots", value: "true"),
			URLQueryItem(name: "order", value: "desc"),
			URLQueryItem(name: "limit", value: "100"),
			URLQueryItem(name: "offset", value: "0"),
		])
	}

	@Test("no filter sends no types")
	func unfiltered() {
		let names = HomerProcessQuery(limit: 50).queryItems.map(\.name)

		#expect(names == ["order", "limit", "offset"])
	}
}
