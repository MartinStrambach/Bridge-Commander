import Foundation
import Testing
@testable import GitHosting

@Suite("GitHub owner token check")
struct GitHubOwnerTokenResponseTests {
	private func verify(_ json: String, owner: String = "acme") throws -> GitHubOwnerTokenVerification {
		try GitHubOwnerTokenResponse.verification(from: Data(json.utf8), owner: owner)
	}

	@Test("an organization that accepts the token is found under GitHub's spelling")
	func organizationFound() throws {
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": {"login": "Acme", "__typename": "Organization"},
		 "organization": {"login": "Acme"}}}
		"""#
		#expect(try verify(json) == GitHubOwnerTokenVerification(login: "someone", owner: "Acme", isOrganization: true))
	}

	@Test("a user owner is found and is no organization")
	func userFound() throws {
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": {"login": "someone", "__typename": "User"},
		 "organization": null},
		 "errors": [{"type": "NOT_FOUND", "path": ["organization"], "message": "Could not resolve to an Organization."}]}
		"""#
		#expect(try verify(json, owner: "someone").isOrganization == false)
	}

	@Test("an organization's refusal fails the check with its reason")
	func organizationRefuses() {
		// The shape api.github.com answered on 2026-11-17, names changed.
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": null, "organization": null},
		 "errors": [{"type": "FORBIDDEN", "path": ["organization"],
		  "message": "The 'acme' organization forbids access via a fine-grained personal access tokens if the token's lifetime is greater than 366 days."}]}
		"""#
		#expect {
			try verify(json)
		} throws: { error in
			guard case let GitHostingError.unauthenticated(reason?) = error else { return false }
			return reason.hasPrefix("The 'acme' organization forbids access")
		}
	}

	@Test("a name GitHub does not know fails as such")
	func ownerNotFound() {
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": null, "organization": null},
		 "errors": [{"type": "NOT_FOUND", "path": ["owner"], "message": "Could not resolve to a RepositoryOwner."}]}
		"""#
		#expect {
			try verify(json, owner: "acme-typo")
		} throws: { error in
			guard case let GitHostingError.ownerNotFound(owner) = error else { return false }
			return owner == "acme-typo"
		}
	}

	@Test("a token that resolves to no user fails as unauthenticated")
	func noViewer() {
		#expect {
			try verify(#"{"data": {"viewer": null, "owner": null}}"#)
		} throws: { error in
			guard case GitHostingError.unauthenticated = error else { return false }
			return true
		}
	}
}
