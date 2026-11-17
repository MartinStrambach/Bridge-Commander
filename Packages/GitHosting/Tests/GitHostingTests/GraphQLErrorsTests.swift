import Foundation
import Testing
@testable import GitHosting

@Suite("GraphQL errors beside the data")
struct GraphQLErrorsTests {
	/// What api.github.com answered a token the organization refuses (2026-11-17), names changed.
	private static let lifetimePolicy = "The 'acme' organization forbids access via a fine-grained personal access "
		+ "tokens if the token's lifetime is greater than 366 days. Please adjust your token's lifetime at the "
		+ "following URL: https://github.com/settings/personal-access-tokens/1"

	private func body(_ errors: String, data: String = "null") -> Data {
		Data(#"{"data": \#(data), "errors": [\#(errors)]}"#.utf8)
	}

	private func error(_ type: String?, _ message: String) -> String {
		let type = type.map { #""type": "\#($0)", "# } ?? ""
		return #"{\#(type)"path": ["repository"], "message": "\#(message)"}"#
	}

	@Test("GitHub's NOT_FOUND for an invisible repository explains nothing")
	func notFoundIsNoExplanation() {
		let json = body(
			error("NOT_FOUND", "Could not resolve to a Repository with the name 'acme/app'."),
			data: #"{"repository": null}"#
		)
		#expect(GraphQLErrorList.explanation(in: json) == nil)
		#expect(GraphQLErrorList.refusal(in: json) == nil)
	}

	@Test("an organization's refusal is read from its own lookup")
	func organizationRefusal() {
		let json = body(error("FORBIDDEN", Self.lifetimePolicy), data: #"{"organization": null}"#)
		#expect(GraphQLErrorList.refusal(in: json) == Self.lifetimePolicy)
	}

	@Test("an owner that is a user, or a token without read:org, is not a refusal")
	func organizationLookupWithoutRefusal() {
		let notFound = body(error("NOT_FOUND", "Could not resolve to an Organization with the login of 'someone'."))
		let scopes = body(error("INSUFFICIENT_SCOPES", "Your token has not been granted the required scopes."))
		let visible = Data(#"{"data": {"organization": {"login": "acme"}}}"#.utf8)
		for json in [notFound, scopes, visible] {
			#expect(GraphQLErrorList.refusal(in: json) == nil)
		}
	}

	@Test("an error other than NOT_FOUND explains a null repository, the first one winning")
	func explanationSkipsNotFound() {
		let json = body([
			error("NOT_FOUND", "Could not resolve to a Repository with the name 'acme/app'."),
			error("FORBIDDEN", "Resource not accessible by personal access token"),
			error("FORBIDDEN", "Another"),
		].joined(separator: ","))
		#expect(GraphQLErrorList.explanation(in: json) == "Resource not accessible by personal access token")
	}

	@Test("GitLab's errors carry no type and explain as they are")
	func typelessError() {
		let json = body(error(nil, "The resource that you are attempting to access does not exist"))
		#expect(GraphQLErrorList.explanation(in: json) == "The resource that you are attempting to access does not exist")
	}

	@Test("a body without errors, or of another shape, explains nothing")
	func noErrors() {
		for json in [#"{"data": {"project": null}}"#, #"{"errors": []}"#, #"{"errors": "nope"}"#, "<html>", ""] {
			#expect(GraphQLErrorList.explanation(in: Data(json.utf8)) == nil)
		}
	}

	@Test("a message is flattened to one line, and one without text is skipped")
	func reasonIsOneLine() {
		let json = body([
			error("FORBIDDEN", #"  \n "#),
			error("FORBIDDEN", #"First line\n\tsecond   line "#),
		].joined(separator: ","))
		#expect(GraphQLErrorList.explanation(in: json) == "First line second line")
	}

	@Test("a message past the limit is cut")
	func reasonIsCapped() throws {
		let json = body(error("FORBIDDEN", String(repeating: "a", count: GraphQLErrorList.reasonLimit + 50)))
		let reason = try #require(GraphQLErrorList.explanation(in: json))
		#expect(reason.count == GraphQLErrorList.reasonLimit + 1)
		#expect(reason.hasSuffix("a…"))
	}

	@Test("only a fine-grained GitHub token gets the hint about its single owner")
	func fineGrainedTokenHint() throws {
		let hint = try #require(GitHubService.fineGrainedTokenHint(token: "github_pat_11ABC", owner: "acme"))
		#expect(hint.contains("create one for acme"))
		#expect(GitHubService.fineGrainedTokenHint(token: "ghp_abc", owner: "acme") == nil)
		#expect(GitHubService.fineGrainedTokenHint(token: "gho_abc", owner: "acme") == nil)
	}
}
