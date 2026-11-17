import ComposableArchitecture
import Foundation
import GitHosting
import Testing
@testable import Settings

@MainActor
@Suite("SettingsReducer GitHub tokens by owner")
struct GitHubOwnerTokenSettingsTests {
	@Test("an owner is listed, given a token, and removed")
	func addSetRemove() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}

		await store.send(.addGitHubOwner("https://github.com/acme/app")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": ""]) }
		}
		// Text that names no owner, or one already listed, changes nothing.
		await store.send(.addGitHubOwner("two words"))
		await store.send(.addGitHubOwner("ACME"))
		await store.send(.setGitHubOwnerToken(owner: "acme", token: " github_pat_org\n")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "github_pat_org"]) }
		}
		await store.send(.removeGitHubOwner("acme")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens() }
		}
	}

	@Test("an owner's test runs against that owner's token, not the main one")
	func testUsesOwnerToken() async {
		let state = SettingsReducer.State()
		state.$githubToken.withLock { $0 = "ghp_main" }
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "github_pat_org", "other": ""]) }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitHubOwnerToken = { token, owner in
				guard !token.isEmpty else {
					throw GitHostingError.missingToken
				}
				return GitHubOwnerTokenVerification(login: "user-of-\(token)", owner: "Acme", isOrganization: true)
			}
		}

		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "acme")) {
			$0.githubOwnerTokenTests = ["acme": .testing]
		}
		await store.receive(\.gitHubOwnerTokenTestFinished) {
			$0.githubOwnerTokenTests = ["acme": .verified(
				message: "Found the Acme organization, and it accepts the token. The token belongs to user-of-github_pat_org. A repository not selected for it still fails on its row."
			)]
		}
		// A listed owner without a token is not tested with the main one.
		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "other")) {
			$0.githubOwnerTokenTests["other"] = .testing
		}
		await store.receive(\.gitHubOwnerTokenTestFinished) {
			$0.githubOwnerTokenTests["other"] = .failure(message: "Enter a token first.")
		}
	}

	@Test("a misspelled owner, an organization's refusal and a user owner each say so")
	func ownerTestMessages() {
		#expect(
			SettingsReducer.ownerTokenTestFailureMessage(for: GitHostingError.ownerNotFound(owner: "acme-typo"), owner: "acme-typo")
				== "GitHub has no user or organization named acme-typo. Use the first part of the repository's address, github.com/owner/repo."
		)
		#expect(
			SettingsReducer.ownerTokenTestFailureMessage(
				for: GitHostingError.unauthenticated(reason: "The 'acme' organization forbids access."),
				owner: "acme"
			) == "The 'acme' organization forbids access."
		)
		#expect(
			SettingsReducer.ownerTokenTestFailureMessage(for: GitHostingError.httpFailure(statusCode: 401), owner: "acme")
				== "HTTP 401 — the token is invalid, revoked, or expired."
		)
		#expect(
			SettingsReducer.ownerTokenVerifiedMessage(
				GitHubOwnerTokenVerification(login: "someone", owner: "someone", isOrganization: false),
				isFineGrained: false
			) == "Found the GitHub user someone. The token belongs to someone."
		)
	}

	@Test("editing or removing an owner's token drops its verdict and leaves the others")
	func editResetsVerdict() async {
		var state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "old", "other": "kept"]) }
		state.githubOwnerTokenTests = ["acme": .success(username: "someone"), "other": .success(username: "someone")]
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}

		await store.send(.setGitHubOwnerToken(owner: "acme", token: "new")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "new", "other": "kept"]) }
			$0.githubOwnerTokenTests = ["other": .success(username: "someone")]
		}
		await store.send(.removeGitHubOwner("other")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "new"]) }
			$0.githubOwnerTokenTests = [:]
		}
	}

	@Test("an owner is acted on as listed: another case reaches its verdict, an unlisted owner is not added back")
	func ownerActionsUseListedOwner() async {
		var state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["Acme": "old"]) }
		state.githubOwnerTokenTests = ["Acme": .success(username: "someone")]
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}

		await store.send(.setGitHubOwnerToken(owner: "ACME", token: "new")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["Acme": "new"]) }
			$0.githubOwnerTokenTests = [:]
		}
		await store.send(.removeGitHubOwner("acme")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens() }
		}
		// A late write from the removed row's field changes nothing.
		await store.send(.setGitHubOwnerToken(owner: "Acme", token: "new"))
		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "Acme"))
	}

	@Test("the import confirmation says owner tokens replace only those owners'")
	func importAlertWording() {
		var backup = SettingsBackup()
		backup.githubOwnerTokens = ["acme": "github_pat_org"]
		let alert = SettingsReducer.importSettingsAlert(backup, skippedRepositoryPaths: [], current: SettingsReducer.State())
		#expect(String(state: alert.message ?? TextState("")).contains("replace only those owners' tokens"))
	}

	@Test("a verdict still in flight does not land under an edited token")
	func editCancelsRunningTest() async {
		let state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "old"]) }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitHubOwnerToken = { _, _ in
				try await Task.never()
			}
		}

		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "acme")) {
			$0.githubOwnerTokenTests = ["acme": .testing]
		}
		await store.send(.setGitHubOwnerToken(owner: "acme", token: "new")) {
			$0.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "new"]) }
			$0.githubOwnerTokenTests = [:]
		}
	}

	// MARK: - Backup

	@Test("owner tokens are exported with the other tokens only, and only those that are set")
	func exportedWithTokens() {
		let state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "github_pat_org", "other": ""]) }
		let date = Date(timeIntervalSince1970: 1_800_000_000)

		let without = SettingsBackup(state: state, includesTokens: false, exportedAt: date)
		#expect(without.githubOwnerTokens == nil)
		#expect(!without.includesTokens)

		let with = SettingsBackup(state: state, includesTokens: true, exportedAt: date)
		#expect(with.githubOwnerTokens == ["acme": "github_pat_org"])
		#expect(with.includesTokens)
	}

	@Test("an owner token alone makes export ask about tokens")
	func exportAsksForOwnerTokens() async {
		let state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "github_pat_org"]) }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}

		await store.send(.exportSettingsButtonTapped) {
			$0.alert = SettingsReducer.exportTokensAlert
		}
	}

	@Test("owner tokens survive the file: written as JSON, read back, applied on another Mac")
	func fileRoundTrip() throws {
		let source = SettingsReducer.State()
		source.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["Acme": "github_pat_org", "listed-only": ""]) }
		let data = try SettingsBackup(state: source, includesTokens: true, exportedAt: Date(timeIntervalSince1970: 0)).encoded()
		#expect(String(decoding: data, as: UTF8.self).contains(#""githubOwnerTokens" : {"#))

		let read = try SettingsBackup.decoded(from: data)
		#expect(read.githubOwnerTokens == ["Acme": "github_pat_org"])

		var target = SettingsReducer.State()
		target.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens() }
		read.apply(to: &target)
		#expect(target.githubOwnerTokens.token(forRepositoryOf: "acme", main: "ghp_main") == "github_pat_org")
	}

	@Test("a file from before owner tokens, or one with a name that is no owner, leaves them alone")
	func olderAndOddFiles() throws {
		var state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "kept"]) }

		let older = try SettingsBackup.decoded(from: Data(#"{"formatVersion": 1, "githubToken": "ghp_x"}"#.utf8))
		#expect(older.githubOwnerTokens == nil)
		older.apply(to: &state)

		let odd = try SettingsBackup.decoded(
			from: Data(#"{"formatVersion": 1, "githubOwnerTokens": {"two words": "x", "@Other": " t\n"}}"#.utf8)
		)
		odd.apply(to: &state)
		#expect(state.githubOwnerTokens.tokens == ["acme": "kept", "Other": "t"])
	}

	@Test("importing replaces the tokens of the owners in the file and keeps the others")
	func importMerges() {
		var state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["Acme": "old", "other": "kept"]) }

		var backup = SettingsBackup()
		backup.githubOwnerTokens = ["acme": " new\n", "third": "added"]
		backup.apply(to: &state)

		#expect(state.githubOwnerTokens.tokens == ["Acme": "new", "other": "kept", "third": "added"])
	}
}
