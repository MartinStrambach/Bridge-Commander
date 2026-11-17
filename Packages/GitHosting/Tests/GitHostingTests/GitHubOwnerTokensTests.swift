import Foundation
import Testing
@testable import GitHosting

@Suite("GitHub tokens by owner")
struct GitHubOwnerTokensTests {
	@Test("a repository uses its owner's token, whatever the case, and the main one otherwise")
	func tokenForRepository() {
		let tokens = GitHubOwnerTokens(tokens: ["Acme-Org": "github_pat_org"])
		#expect(tokens.token(forRepositoryOf: "acme-org", main: "ghp_main") == "github_pat_org")
		#expect(tokens.token(forRepositoryOf: "someone", main: "ghp_main") == "ghp_main")
		#expect(tokens.token(forRepositoryOf: "someone", main: "") == "")
	}

	@Test("an owner listed without a token falls back to the main one")
	func ownerWithoutToken() {
		var tokens = GitHubOwnerTokens()
		tokens.add("acme")
		#expect(tokens.token(forOwner: "acme") == "")
		#expect(!tokens.hasTokens)
		#expect(tokens.token(forRepositoryOf: "acme", main: "ghp_main") == "ghp_main")
	}

	@Test("an owner is listed once, and adding it again keeps its token")
	func addIsIdempotent() {
		var tokens = GitHubOwnerTokens()
		tokens.setToken(" github_pat_org\n", forOwner: "Acme")
		tokens.add("acme")
		tokens.add("  ")
		#expect(tokens.tokens == ["Acme": "github_pat_org"])

		tokens.setToken("github_pat_new", forOwner: "ACME")
		#expect(tokens.tokens == ["Acme": "github_pat_new"])
		#expect(tokens.hasTokens)

		tokens.remove("acme")
		#expect(tokens.tokens.isEmpty)
	}

	@Test("owners are listed alphabetically, case aside")
	func ownersOrder() {
		let tokens = GitHubOwnerTokens(tokens: ["zeta": "", "Acme": "", "beta": ""])
		#expect(tokens.owners == ["Acme", "beta", "zeta"])
	}

	@Test("an owner is read from a login, a mention, a repository or a link")
	func normalizedOwner() {
		for text in ["acme", " acme ", "@acme", "acme/app", "github.com/acme", "https://github.com/acme/app/pulls"] {
			#expect(GitHubOwnerTokens.normalizedOwner(text) == "acme")
		}
		#expect(GitHubOwnerTokens.normalizedOwner("Acme-Org1") == "Acme-Org1")
		for text in ["", "  ", "/", "two words", "acme.org", "ac\"me"] {
			#expect(GitHubOwnerTokens.normalizedOwner(text) == nil)
		}
	}

	@Test("the stored form reads back, and owners differing only in case are folded into one")
	func rawValueRoundTrip() throws {
		let tokens = GitHubOwnerTokens(tokens: ["acme": "github_pat_org", "someone": ""])
		#expect(tokens.rawValue == #"{"acme":"github_pat_org","someone":""}"#)
		#expect(GitHubOwnerTokens(rawValue: tokens.rawValue) == tokens)
		#expect(GitHubOwnerTokens(rawValue: "not json") == nil)

		let folded = try #require(GitHubOwnerTokens(rawValue: #"{"Acme":"first","acme":"second"}"#))
		#expect(folded.tokens == ["Acme": "second"])
	}
}
