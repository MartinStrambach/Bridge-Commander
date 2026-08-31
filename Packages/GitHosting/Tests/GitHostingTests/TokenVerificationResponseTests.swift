import Foundation
import Testing
@testable import GitHosting

@Suite("Token verification GraphQL responses")
struct TokenVerificationResponseTests {
	@Test("GitLab response yields the authenticated username")
	func gitLabUsername() throws {
		let json = #"{"data": {"currentUser": {"username": "branislav.bily1"}}}"#
		let decoded = try JSONDecoder().decode(GitLabCurrentUserResponse.self, from: Data(json.utf8))
		#expect(decoded.username == "branislav.bily1")
	}

	@Test("GitLab null currentUser yields nil — an accepted but identity-less request")
	func gitLabNullUser() throws {
		for json in [#"{"data": {"currentUser": null}}"#, #"{"data": null}"#, "{}"] {
			let decoded = try JSONDecoder().decode(GitLabCurrentUserResponse.self, from: Data(json.utf8))
			#expect(decoded.username == nil)
		}
	}

	@Test("GitHub response yields the authenticated login")
	func gitHubLogin() throws {
		let json = #"{"data": {"viewer": {"login": "octocat"}}}"#
		let decoded = try JSONDecoder().decode(GitHubViewerResponse.self, from: Data(json.utf8))
		#expect(decoded.login == "octocat")
	}

	@Test("GitHub missing viewer yields nil")
	func gitHubMissingViewer() throws {
		for json in [#"{"data": {"viewer": null}}"#, #"{"data": null}"#, "{}"] {
			let decoded = try JSONDecoder().decode(GitHubViewerResponse.self, from: Data(json.utf8))
			#expect(decoded.login == nil)
		}
	}
}
