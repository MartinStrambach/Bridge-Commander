import Foundation
import Testing
@testable import GitHosting

@Suite("GitHub owner token check")
struct GitHubOwnerTokenResponseTests {
	private typealias Found = GitHubOwnerTokenResponse.Found

	private func found(_ json: String) throws -> Found {
		try GitHubOwnerTokenResponse.found(in: Data(json.utf8))
	}

	@Test("an organization is found under GitHub's spelling")
	func organizationFound() throws {
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": {"login": "Acme", "__typename": "Organization"}}}
		"""#
		let result = try found(json)
		#expect(result == Found(login: "someone", owner: ("Acme", true)))
		#expect(try GitHubOwnerTokenVerification(found: result, owner: "acme")
			== GitHubOwnerTokenVerification(login: "someone", owner: "Acme", isOrganization: true))
	}

	@Test("a user owner is found and is no organization")
	func userFound() throws {
		let json = #"{"data": {"viewer": {"login": "someone"}, "owner": {"login": "someone", "__typename": "User"}}}"#
		#expect(try found(json).owner?.isOrganization == false)
	}

	@Test("a refusal anywhere in the answer fails the check with its reason")
	func refusal() {
		// Not seen for this query; the organization lookup's refusal (2026-11-17) is the model.
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": null},
		 "errors": [{"type": "FORBIDDEN", "path": ["owner"], "message": "The 'acme' organization forbids access."}]}
		"""#
		#expect {
			try found(json)
		} throws: { error in
			guard case let GitHostingError.unauthenticated(reason?) = error else { return false }
			return reason == "The 'acme' organization forbids access."
		}
	}

	@Test("a name GitHub does not know fails as such")
	func ownerNotFound() throws {
		let json = #"""
		{"data": {"viewer": {"login": "someone"}, "owner": null},
		 "errors": [{"type": "NOT_FOUND", "path": ["owner"], "message": "Could not resolve to a RepositoryOwner."}]}
		"""#
		let result = try found(json)
		#expect(result.owner == nil)
		#expect {
			try GitHubOwnerTokenVerification(found: result, owner: "acme-typo")
		} throws: { error in
			guard case let GitHostingError.ownerNotFound(owner) = error else { return false }
			return owner == "acme-typo"
		}
	}

	@Test("a token that resolves to no user fails as unauthenticated")
	func noViewer() {
		#expect {
			try found(#"{"data": {"viewer": null, "owner": null}}"#)
		} throws: { error in
			guard case GitHostingError.unauthenticated = error else { return false }
			return true
		}
	}
}
