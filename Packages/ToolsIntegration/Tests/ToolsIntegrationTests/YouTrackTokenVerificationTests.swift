import Foundation
import Testing
@testable import ToolsIntegration

@Suite("YouTrack token verification")
struct YouTrackTokenVerificationTests {
	@Test("the current user's login is what the test reports")
	func parsesLogin() throws {
		let data = Data(#"{"login":"martin.strambach","name":"Martin Strambach","$type":"Me"}"#.utf8)
		#expect(try YouTrackService.parseCurrentUser(from: data) == "martin.strambach")
	}

	@Test("a user without a login falls back to the display name")
	func fallsBackToName() throws {
		let data = Data(#"{"name":"Martin Strambach","$type":"Me"}"#.utf8)
		#expect(try YouTrackService.parseCurrentUser(from: data) == "Martin Strambach")
	}

	@Test("a 200 that is not a YouTrack user is an unexpected response", arguments: [
		"<!doctype html><html></html>",
		#"{"$type":"Me"}"#,
		"[]",
	])
	func rejectsNonUser(body: String) {
		#expect(throws: YouTrackServiceError.self) {
			try YouTrackService.parseCurrentUser(from: Data(body.utf8))
		}
	}

	@Test("missing token or base URL fails before any request")
	func validatesInputs() async {
		await #expect(throws: YouTrackServiceError.self) {
			try await YouTrackService.verifyToken(baseURL: "https://org.youtrack.cloud", authToken: "")
		}
		await #expect(throws: YouTrackServiceError.self) {
			try await YouTrackService.verifyToken(baseURL: "  ", authToken: "perm:abc")
		}
	}
}
