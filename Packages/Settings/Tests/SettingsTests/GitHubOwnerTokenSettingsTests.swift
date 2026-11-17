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
			$0[TokenVerificationClient.self].verifyGitHubToken = { token in
				guard !token.isEmpty else {
					throw GitHostingError.missingToken
				}
				return "user-of-\(token)"
			}
		}

		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "acme")) {
			$0.githubOwnerTokenTests = ["acme": .testing]
		}
		await store.receive(\.gitHubOwnerTokenTestFinished) {
			$0.githubOwnerTokenTests = ["acme": .success(username: "user-of-github_pat_org")]
		}
		// A listed owner without a token is not tested with the main one.
		await store.send(.testGitHubOwnerTokenButtonTapped(owner: "other")) {
			$0.githubOwnerTokenTests["other"] = .testing
		}
		await store.receive(\.gitHubOwnerTokenTestFinished) {
			$0.githubOwnerTokenTests["other"] = .failure(message: "Enter a token first.")
		}
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

	@Test("a verdict still in flight does not land under an edited token")
	func editCancelsRunningTest() async {
		let state = SettingsReducer.State()
		state.$githubOwnerTokens.withLock { $0 = GitHubOwnerTokens(tokens: ["acme": "old"]) }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitHubToken = { _ in
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
