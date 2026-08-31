import ComposableArchitecture
import Foundation
import GitHosting
import Testing
@testable import Settings

@MainActor
@Suite("SettingsReducer")
struct SettingsReducerTests {
	// MARK: - Group default-branch trimming

	@Test("setGroupDefaultBranch trims surrounding whitespace and newlines")
	func setGroupDefaultBranchTrimsWhitespace() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupDefaultBranch(groupId: "repo", value: "  develop \n")) {
			$0.groupSettings["repo"] = RepoGroupSettings(defaultBranch: "develop")
		}
	}

	@Test("setGroupDefaultBranch stores a whitespace-only value as empty (master/main fallback)")
	func setGroupDefaultBranchWhitespaceOnlyBecomesEmpty() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupDefaultBranch(groupId: "repo", value: "   \n\t")) {
			$0.groupSettings["repo"] = RepoGroupSettings(defaultBranch: "")
		}
	}

	// MARK: - Group YouTrack base URL trimming

	@Test("setGroupYouTrackBaseURL trims surrounding whitespace and newlines")
	func setGroupYouTrackBaseURLTrimsWhitespace() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "repo", value: "  https://youtrack.example.com \n")) {
			$0.groupSettings["repo"] = RepoGroupSettings(youtrackBaseURL: "https://youtrack.example.com")
		}
	}

	@Test("setGroupYouTrackBaseURL stores a whitespace-only value as empty (integration disabled)")
	func setGroupYouTrackBaseURLWhitespaceOnlyBecomesEmpty() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "repo", value: "   \n\t")) {
			$0.groupSettings["repo"] = RepoGroupSettings(youtrackBaseURL: "")
		}
	}

	// MARK: - Token trimming

	@Test("token setters trim pasted whitespace and newlines")
	func tokenSettersTrimWhitespace() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGitLabToken("glpat-abc123\n")) {
			$0.gitlabToken = "glpat-abc123"
		}
		await store.send(.setGitHubToken("  ghp_abc123 ")) {
			$0.githubToken = "ghp_abc123"
		}
		await store.send(.setYouTrackToken("perm:abc.123\t\n")) {
			$0.youtrackAuthToken = "perm:abc.123"
		}
	}

	// MARK: - Token connection test

	@Test("a passing GitLab token test reports the authenticated username")
	func gitLabTokenTestSuccess() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitLabToken = { _ in "branislav.bily1" }
		}
		await store.send(.testGitLabTokenButtonTapped) {
			$0.gitlabTokenTest = .testing
		}
		await store.receive(\.gitLabTokenTestFinished) {
			$0.gitlabTokenTest = .success(username: "branislav.bily1")
		}
	}

	@Test("a passing GitHub token test reports the authenticated login")
	func gitHubTokenTestSuccess() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitHubToken = { _ in "octocat" }
		}
		await store.send(.testGitHubTokenButtonTapped) {
			$0.githubTokenTest = .testing
		}
		await store.receive(\.gitHubTokenTestFinished) {
			$0.githubTokenTest = .success(username: "octocat")
		}
	}

	@Test("a 401 failure explains the token is invalid")
	func tokenTestUnauthorized() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitLabToken = { _ in
				throw GitHostingError.httpFailure(statusCode: 401)
			}
		}
		await store.send(.testGitLabTokenButtonTapped) {
			$0.gitlabTokenTest = .testing
		}
		await store.receive(\.gitLabTokenTestFinished) {
			$0.gitlabTokenTest = .failure(message: "HTTP 401 — the token is invalid, revoked, or expired.")
		}
	}

	@Test("a GitLab identity-less response points at fine-grained token limits")
	func gitLabTokenTestUnauthenticated() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitLabToken = { _ in
				throw GitHostingError.unauthenticated
			}
		}
		await store.send(.testGitLabTokenButtonTapped) {
			$0.gitlabTokenTest = .testing
		}
		await store.receive(\.gitLabTokenTestFinished) {
			$0.gitlabTokenTest = .failure(
				message: "GitLab accepted the request but returned no user. Fine-grained tokens cannot use the GraphQL API this app relies on — use a personal, project, or group token with the read_api scope."
			)
		}
	}

	@Test("an empty token fails with a prompt to enter one")
	func tokenTestMissingToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitLabToken = { _ in
				throw GitHostingError.missingToken
			}
		}
		await store.send(.testGitLabTokenButtonTapped) {
			$0.gitlabTokenTest = .testing
		}
		await store.receive(\.gitLabTokenTestFinished) {
			$0.gitlabTokenTest = .failure(message: "Enter a token first.")
		}
	}

	@Test("editing or clearing a token drops its stale test verdict")
	func tokenEditResetsTestState() async {
		var state = SettingsReducer.State()
		state.gitlabTokenTest = .success(username: "someone")
		state.githubTokenTest = .failure(message: "HTTP 500.")
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}
		await store.send(.setGitLabToken("glpat-new")) {
			$0.gitlabToken = "glpat-new"
			$0.gitlabTokenTest = .idle
		}
		await store.send(.clearGitHubToken) {
			$0.githubToken = ""
			$0.githubTokenTest = .idle
		}
	}

	// MARK: - Group default insertion

	@Test("mutating an unknown group inserts a default RepoGroupSettings with only that field changed")
	func setGroupFieldInsertsDefaultForUnknownGroup() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupSupportsIOS(groupId: "new-group", value: true)) {
			$0.groupSettings["new-group"] = RepoGroupSettings(supportsIOS: true)
		}
	}

	@Test("multiple group mutations accumulate on the same RepoGroupSettings")
	func multipleGroupMutationsAccumulate() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupSupportsIOS(groupId: "g", value: true)) {
			$0.groupSettings["g"] = RepoGroupSettings(supportsIOS: true)
		}
		await store.send(.setGroupTicketIdRegex(groupId: "g", regex: "MOB-[0-9]+")) {
			$0.groupSettings["g"]?.ticketIdRegex = "MOB-[0-9]+"
		}
		await store.send(.setGroupSupportsTuist(groupId: "g", value: true)) {
			$0.groupSettings["g"]?.supportsTuist = true
		}
	}

	// MARK: - Clear-token alert flow

	@Test("clearTokenButtonTapped presents a confirmation alert")
	func clearTokenButtonPresentsAlert() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.clearTokenButtonTapped) {
			$0.alert = AlertState {
				TextState("Clear Token")
			} actions: {
				ButtonState(role: .destructive, action: .confirmClearToken) {
					TextState("Clear")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(
					"Are you sure you want to clear the token? YouTrack features will not work without a valid token."
				)
			}
		}
	}

	@Test("confirming the alert clears the YouTrack token and dismisses the alert")
	func confirmingAlertClearsToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setYouTrackToken("secret-token")) {
			$0.youtrackAuthToken = "secret-token"
		}
		await store.send(.clearTokenButtonTapped) {
			$0.alert = AlertState {
				TextState("Clear Token")
			} actions: {
				ButtonState(role: .destructive, action: .confirmClearToken) {
					TextState("Clear")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(
					"Are you sure you want to clear the token? YouTrack features will not work without a valid token."
				)
			}
		}
		await store.send(.alert(.presented(.confirmClearToken))) {
			$0.youtrackAuthToken = ""
			$0.alert = nil
		}
	}

	@Test("dismissing the alert leaves the YouTrack token untouched")
	func dismissingAlertKeepsToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setYouTrackToken("keep-me")) {
			$0.youtrackAuthToken = "keep-me"
		}
		await store.send(.clearTokenButtonTapped) {
			$0.alert = AlertState {
				TextState("Clear Token")
			} actions: {
				ButtonState(role: .destructive, action: .confirmClearToken) {
					TextState("Clear")
				}
				ButtonState(role: .cancel) {
					TextState("Cancel")
				}
			} message: {
				TextState(
					"Are you sure you want to clear the token? YouTrack features will not work without a valid token."
				)
			}
		}
		await store.send(.alert(.dismiss)) {
			$0.alert = nil
		}
		#expect(store.state.youtrackAuthToken == "keep-me")
	}

	// MARK: - Representative scalar setters

	@Test("clearGitHubToken empties the GitHub token")
	func clearGitHubToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGitHubToken("ghp_abc")) {
			$0.githubToken = "ghp_abc"
		}
		await store.send(.clearGitHubToken) {
			$0.githubToken = ""
		}
	}

	@Test("setPeriodicRefreshInterval updates the shared interval")
	func setPeriodicRefreshInterval() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setPeriodicRefreshInterval(.thirtyMinutes)) {
			$0.periodicRefreshInterval = .thirtyMinutes
		}
	}

	@Test("setBranchNameRegex updates the shared regex")
	func setBranchNameRegex() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setBranchNameRegex("FOO-[0-9]+")) {
			$0.branchNameRegex = "FOO-[0-9]+"
		}
	}
}
