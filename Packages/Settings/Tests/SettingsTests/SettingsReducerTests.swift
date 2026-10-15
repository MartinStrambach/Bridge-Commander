import ComposableArchitecture
import Foundation
import GitHosting
import Testing
import ToolsIntegration
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
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(defaultBranch: "develop") }
		}
	}

	@Test("setGroupDefaultBranch stores a whitespace-only value as empty (master/main fallback)")
	func setGroupDefaultBranchWhitespaceOnlyBecomesEmpty() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupDefaultBranch(groupId: "repo", value: "   \n\t")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(defaultBranch: "") }
		}
	}

	// MARK: - Group terminal startup command

	@Test("setGroupTerminalStartupCommand stores each keystroke as typed, spaces included")
	func setGroupTerminalStartupCommandKeepsSpaces() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		// The TextField writes on every keystroke; trimming here would eat the space between words.
		await store.send(.setGroupTerminalStartupCommand(groupId: "repo", value: "mise ")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(terminalStartupCommand: "mise ") }
		}
		await store.send(.setGroupTerminalStartupCommand(groupId: "repo", value: "mise install")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(terminalStartupCommand: "mise install") }
		}
	}

	@Test("setGroupTerminalStartupCommand leaves the group's other settings alone")
	func setGroupTerminalStartupCommandKeepsOtherSettings() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupDefaultBranch(groupId: "repo", value: "develop")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(defaultBranch: "develop") }
		}
		await store.send(.setGroupTerminalStartupCommand(groupId: "repo", value: "claude")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(defaultBranch: "develop", terminalStartupCommand: "claude") }
		}
		await store.send(.setGroupTerminalStartupCommand(groupId: "repo", value: "")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(defaultBranch: "develop") }
		}
	}

	@Test("setGroupSkipGlobalTerminalStartupCommand toggles the group's opt-out")
	func setGroupSkipGlobalTerminalStartupCommand() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupSkipGlobalTerminalStartupCommand(groupId: "repo", value: true)) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(skipGlobalTerminalStartupCommand: true) }
		}
		await store.send(.setGroupSkipGlobalTerminalStartupCommand(groupId: "repo", value: false)) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings() }
		}
	}

	@Test("setTerminalStartupCommand stores the global command as typed")
	func setTerminalStartupCommandKeepsSpaces() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setTerminalStartupCommand("mise ")) {
			$0.$terminalStartupCommand.withLock { $0 = "mise " }
		}
		await store.send(.setTerminalStartupCommand("mise install")) {
			$0.$terminalStartupCommand.withLock { $0 = "mise install" }
		}
	}

	@Test("the startup command stays out of new tabs until the user turns that on")
	func terminalStartupCommandInNewTabsDefaultsToOff() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalStartupCommandInNewTabs == false)

		await store.send(.setTerminalStartupCommandInNewTabs(true)) {
			$0.$terminalStartupCommandInNewTabs.withLock { $0 = true }
		}
		await store.send(.setTerminalStartupCommandInNewTabs(false)) {
			$0.$terminalStartupCommandInNewTabs.withLock { $0 = false }
		}
	}

	// MARK: - Built-in terminal

	@Test("copy-on-select is off until the user turns it on")
	func terminalCopyOnSelectDefaultsToOff() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalCopyOnSelect == false)

		await store.send(.setTerminalCopyOnSelect(true)) {
			$0.$terminalCopyOnSelect.withLock { $0 = true }
		}
		await store.send(.setTerminalCopyOnSelect(false)) {
			$0.$terminalCopyOnSelect.withLock { $0 = false }
		}
	}

	@Test("mouse reporting is on until the user turns it off")
	func terminalMouseReportingDefaultsToOn() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalMouseReporting == true)

		await store.send(.setTerminalMouseReporting(false)) {
			$0.$terminalMouseReporting.withLock { $0 = false }
		}
		await store.send(.setTerminalMouseReporting(true)) {
			$0.$terminalMouseReporting.withLock { $0 = true }
		}
	}

	@Test("terminal notifications are on until the user turns them off")
	func terminalNotificationsDefaultToOn() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalNotifications == true)

		await store.send(.setTerminalNotifications(false)) {
			$0.$terminalNotifications.withLock { $0 = false }
		}
		await store.send(.setTerminalNotifications(true)) {
			$0.$terminalNotifications.withLock { $0 = true }
		}
	}

	@Test("Claude status detection uses progress reports and the screen until changed")
	func terminalClaudeStatusDetectionDefaultsToBoth() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalClaudeStatusDetection == .progressAndScreen)

		await store.send(.setTerminalClaudeStatusDetection(.progressOnly)) {
			$0.$terminalClaudeStatusDetection.withLock { $0 = .progressOnly }
		}
		await store.send(.setTerminalClaudeStatusDetection(.screenOnly)) {
			$0.$terminalClaudeStatusDetection.withLock { $0 = .screenOnly }
		}
	}

	@Test("font size starts at the size the terminal already used and is clamped when set")
	func terminalFontSizeDefaultsAndClamps() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		#expect(store.state.terminalFontSize == TerminalFontSize.default)

		await store.send(.setTerminalFontSize(16)) {
			$0.$terminalFontSize.withLock { $0 = 16 }
		}
		await store.send(.setTerminalFontSize(999)) {
			$0.$terminalFontSize.withLock { $0 = TerminalFontSize.maximum }
		}
		await store.send(.setTerminalFontSize(0)) {
			$0.$terminalFontSize.withLock { $0 = TerminalFontSize.minimum }
		}
	}

	// MARK: - Group YouTrack base URL trimming

	@Test("setGroupYouTrackBaseURL trims surrounding whitespace and newlines")
	func setGroupYouTrackBaseURLTrimsWhitespace() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "repo", value: "  https://youtrack.example.com \n")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(youtrackBaseURL: "https://youtrack.example.com") }
		}
	}

	@Test("setGroupYouTrackBaseURL stores a whitespace-only value as empty (integration disabled)")
	func setGroupYouTrackBaseURLWhitespaceOnlyBecomesEmpty() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "repo", value: "   \n\t")) {
			$0.$groupSettings.withLock { $0["repo"] = RepoGroupSettings(youtrackBaseURL: "") }
		}
	}

	// MARK: - Token trimming

	@Test("token setters trim pasted whitespace and newlines")
	func tokenSettersTrimWhitespace() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGitLabToken("glpat-abc123\n")) {
			$0.$gitlabToken.withLock { $0 = "glpat-abc123" }
		}
		await store.send(.setGitHubToken("  ghp_abc123 ")) {
			$0.$githubToken.withLock { $0 = "ghp_abc123" }
		}
		await store.send(.setYouTrackToken("perm:abc.123\t\n")) {
			$0.$youtrackAuthToken.withLock { $0 = "perm:abc.123" }
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
			$0.$gitlabToken.withLock { $0 = "glpat-new" }
			$0.gitlabTokenTest = .idle
		}
		await store.send(.clearGitHubToken) {
			$0.$githubToken.withLock { $0 = "" }
			$0.githubTokenTest = .idle
		}
	}

	// MARK: - YouTrack token connection test

	/// Seeds the shared settings the test is reading. Written through `@Shared` after the store
	/// exists, so they land in the store's own storage rather than in a state built beforehand.
	private func seedYouTrack(token: String = "perm:abc", urls: [String: String]) {
		@Shared(.youtrackAuthToken) var youtrackAuthToken = ""
		@Shared(.trackedRepoPaths) var trackedRepoPaths: [String] = []
		@Shared(.groupSettings) var groupSettings: [String: RepoGroupSettings] = [:]
		$youtrackAuthToken.withLock { $0 = token }
		$trackedRepoPaths.withLock { $0 = urls.keys.sorted() }
		$groupSettings.withLock { settings in
			for (groupId, url) in urls {
				settings[groupId] = RepoGroupSettings(youtrackBaseURL: url)
			}
		}
	}

	@Test("a passing YouTrack token test names the login and the instance")
	func youTrackTokenTestSuccess() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[YouTrackClient.self].verifyToken = { baseURL, token in
				#expect(baseURL == "https://org.youtrack.cloud")
				#expect(token == "perm:abc")
				return "jdoe"
			}
		}
		seedYouTrack(urls: ["/repo": "https://org.youtrack.cloud/"])
		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.receive(\.youTrackTokenTestFinished) {
			$0.youtrackTokenTest = .success(username: "jdoe on org.youtrack.cloud")
		}
	}

	@Test("groups sharing an instance are tested once; a failure names its instance")
	func youTrackTokenTestPerInstance() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[YouTrackClient.self].verifyToken = { baseURL, _ in
				guard baseURL == "https://one.youtrack.cloud" else {
					throw YouTrackServiceError.httpFailure(statusCode: 401)
				}
				return "jdoe"
			}
		}
		seedYouTrack(urls: [
			"/a": "https://one.youtrack.cloud",
			"/b": "https://one.youtrack.cloud/api",
			"/c": "https://two.youtrack.cloud",
			"/d": "",
		])
		#expect(SettingsReducer.youTrackInstances(in: store.state) == [
			"https://one.youtrack.cloud",
			"https://two.youtrack.cloud",
		])
		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.receive(\.youTrackTokenTestFinished) {
			$0.youtrackTokenTest = .failure(message: """
			one.youtrack.cloud: authenticated as jdoe
			two.youtrack.cloud: HTTP 401 — the token is invalid, revoked, or expired.
			""")
		}
	}

	@Test("a URL that does not answer as YouTrack points at the group's URL")
	func youTrackTokenTestWrongURL() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[YouTrackClient.self].verifyToken = { _, _ in throw YouTrackServiceError.unexpectedResponse }
		}
		seedYouTrack(urls: ["/repo": "https://example.com"])
		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.receive(\.youTrackTokenTestFinished) {
			$0.youtrackTokenTest = .failure(
				message: "example.com: no YouTrack API answered at this URL — check the group's YouTrack URL."
			)
		}
	}

	@Test("without a token the test fails without a request")
	func youTrackTokenTestNeedsToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		seedYouTrack(token: "", urls: ["/repo": "https://org.youtrack.cloud"])
		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .failure(message: "Enter a token first.")
		}
	}

	@Test("without any group's YouTrack URL the test fails without a request")
	func youTrackTokenTestNeedsURL() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		seedYouTrack(urls: ["/repo": ""])
		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .failure(
				message: "Set a YouTrack URL on a repository group (Repository Groups below) to test against."
			)
		}
	}

	@Test("editing the YouTrack token or a group's URL drops the stale verdict")
	func youTrackEditResetsTestState() async {
		var state = SettingsReducer.State()
		state.youtrackTokenTest = .success(username: "jdoe on org.youtrack.cloud")
		let store = TestStore(initialState: state) {
			SettingsReducer()
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "/repo", value: "https://new.youtrack.cloud")) {
			$0.$groupSettings.withLock { $0["/repo"] = RepoGroupSettings(youtrackBaseURL: "https://new.youtrack.cloud") }
			$0.youtrackTokenTest = .idle
		}
		await store.send(.youTrackTokenTestFinished(.failure(message: "HTTP 500."))) {
			$0.youtrackTokenTest = .failure(message: "HTTP 500.")
		}
		await store.send(.setYouTrackToken("perm:new")) {
			$0.$youtrackAuthToken.withLock { $0 = "perm:new" }
			$0.youtrackTokenTest = .idle
		}
	}

	// MARK: - Token test cancellation

	@Test("editing the GitHub token cancels a test still in flight for the old one")
	func gitHubTokenEditCancelsTest() async {
		let clock = TestClock()
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitHubToken = { _ in
				try await clock.sleep(for: .seconds(1))
				return "old-login"
			}
		}
		await store.send(.testGitHubTokenButtonTapped) {
			$0.githubTokenTest = .testing
		}
		await store.send(.setGitHubToken("ghp_new")) {
			$0.$githubToken.withLock { $0 = "ghp_new" }
			$0.githubTokenTest = .idle
		}
		// Had the old run survived, it would now deliver "authenticated as old-login" for the new token.
		await clock.advance(by: .seconds(1))
		#expect(store.state.githubTokenTest == .idle)
	}

	@Test("clearing the GitLab token cancels a test still in flight")
	func gitLabTokenClearCancelsTest() async {
		let clock = TestClock()
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: {
			$0[TokenVerificationClient.self].verifyGitLabToken = { _ in
				try await clock.sleep(for: .seconds(1))
				return "old-user"
			}
		}
		await store.send(.setGitLabToken("glpat-old")) {
			$0.$gitlabToken.withLock { $0 = "glpat-old" }
		}
		await store.send(.testGitLabTokenButtonTapped) {
			$0.gitlabTokenTest = .testing
		}
		await store.send(.clearGitLabToken) {
			$0.$gitlabToken.withLock { $0 = "" }
			$0.gitlabTokenTest = .idle
		}
		await clock.advance(by: .seconds(1))
		#expect(store.state.gitlabTokenTest == .idle)
	}

	@Test("changing the YouTrack token, a group's URL, or clearing the token cancels a test in flight")
	func youTrackEditsCancelTest() async {
		let clock = TestClock()
		var state = SettingsReducer.State()
		state.alert = AlertState { TextState("Clear Token") }
		let store = TestStore(initialState: state) {
			SettingsReducer()
		} withDependencies: {
			$0[YouTrackClient.self].verifyToken = { _, _ in
				try await clock.sleep(for: .seconds(1))
				return "jdoe"
			}
		}
		seedYouTrack(urls: ["/repo": "https://org.youtrack.cloud"])

		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.send(.setGroupYouTrackBaseURL(groupId: "/repo", value: "https://new.youtrack.cloud")) {
			$0.$groupSettings.withLock { $0["/repo"] = RepoGroupSettings(youtrackBaseURL: "https://new.youtrack.cloud") }
			$0.youtrackTokenTest = .idle
		}
		await clock.advance(by: .seconds(1))

		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.send(.setYouTrackToken("perm:new")) {
			$0.$youtrackAuthToken.withLock { $0 = "perm:new" }
			$0.youtrackTokenTest = .idle
		}
		await clock.advance(by: .seconds(1))

		await store.send(.testYouTrackTokenButtonTapped) {
			$0.youtrackTokenTest = .testing
		}
		await store.send(.alert(.presented(.confirmClearToken))) {
			$0.$youtrackAuthToken.withLock { $0 = "" }
			$0.youtrackTokenTest = .idle
			$0.alert = nil
		}
		await clock.advance(by: .seconds(1))
		#expect(store.state.youtrackTokenTest == .idle)
	}

	// MARK: - Group default insertion

	@Test("mutating an unknown group inserts a default RepoGroupSettings with only that field changed")
	func setGroupFieldInsertsDefaultForUnknownGroup() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupSupportsIOS(groupId: "new-group", value: true)) {
			$0.$groupSettings.withLock { $0["new-group"] = RepoGroupSettings(supportsIOS: true) }
		}
	}

	@Test("multiple group mutations accumulate on the same RepoGroupSettings")
	func multipleGroupMutationsAccumulate() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGroupSupportsIOS(groupId: "g", value: true)) {
			$0.$groupSettings.withLock { $0["g"] = RepoGroupSettings(supportsIOS: true) }
		}
		await store.send(.setGroupTicketIdRegex(groupId: "g", regex: "MOB-[0-9]+")) {
			$0.$groupSettings.withLock { $0["g"]?.ticketIdRegex = "MOB-[0-9]+" }
		}
		await store.send(.setGroupSupportsTuist(groupId: "g", value: true)) {
			$0.$groupSettings.withLock { $0["g"]?.supportsTuist = true }
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
			$0.$youtrackAuthToken.withLock { $0 = "secret-token" }
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
			$0.$youtrackAuthToken.withLock { $0 = "" }
			$0.alert = nil
		}
	}

	@Test("dismissing the alert leaves the YouTrack token untouched")
	func dismissingAlertKeepsToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setYouTrackToken("keep-me")) {
			$0.$youtrackAuthToken.withLock { $0 = "keep-me" }
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

	// MARK: - DerivedData usage

	@Test("measuring DerivedData shows each partial usage and ends when the scan does")
	func measuresDerivedDataUsage() async {
		let partial = DerivedDataUsage(
			tallies: [.inUse: .init(folders: 1), .orphaned: .init(folders: 1)],
			measuredFolders: 0,
			totalFolders: 2
		)
		var complete = partial
		complete.tallies[.inUse]?.bytes = 2048
		complete.tallies[.orphaned]?.bytes = 1024
		complete.measuredFolders = 2
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		} withDependencies: { [partial, complete] in
			$0[DerivedDataUsageClient.self].measure = {
				AsyncStream { continuation in
					continuation.yield(partial)
					continuation.yield(complete)
					continuation.finish()
				}
			}
		}
		await store.send(.measureDerivedDataButtonTapped) {
			$0.isMeasuringDerivedData = true
		}
		await store.receive(\.derivedDataUsageUpdated) {
			$0.derivedDataUsage = partial
		}
		await store.receive(\.derivedDataUsageUpdated) {
			$0.derivedDataUsage = complete
		}
		await store.receive(\.derivedDataMeasurementFinished) {
			$0.isMeasuringDerivedData = false
		}
	}

	@Test("deleting orphaned DerivedData asks first, then deletes and measures again")
	func deletesOrphanedDerivedData() async {
		let measured = DerivedDataUsage(
			tallies: [.inUse: .init(folders: 1, bytes: 4096), .orphaned: .init(folders: 2, bytes: 2048)],
			measuredFolders: 3,
			totalFolders: 3
		)
		let remeasured = DerivedDataUsage(
			tallies: [.inUse: .init(folders: 1, bytes: 4096)],
			measuredFolders: 1,
			totalFolders: 1
		)
		var initialState = SettingsReducer.State()
		initialState.derivedDataUsage = measured
		let deletedKinds = LockIsolated<[DerivedDataUsage.Kind]>([])
		let store = TestStore(initialState: initialState) {
			SettingsReducer()
		} withDependencies: { [remeasured] in
			$0[DerivedDataUsageClient.self].deleteFolders = { kind in
				deletedKinds.withValue { $0.append(kind) }
				return DerivedDataDeletion(deletedFolders: 2)
			}
			$0[DerivedDataUsageClient.self].measure = {
				AsyncStream { continuation in
					continuation.yield(remeasured)
					continuation.finish()
				}
			}
		}

		await store.send(.deleteDerivedDataButtonTapped(.orphaned)) {
			$0.alert = SettingsReducer.deleteDerivedDataAlert(kind: .orphaned, tally: .init(folders: 2, bytes: 2048))
		}
		await store.send(.alert(.presented(.confirmDeleteDerivedData(.orphaned)))) {
			$0.alert = nil
			$0.deletingDerivedDataKind = .orphaned
		}
		await store.receive(\.derivedDataDeletionFinished) {
			$0.deletingDerivedDataKind = nil
			$0.isMeasuringDerivedData = true
		}
		await store.receive(\.derivedDataUsageUpdated) {
			$0.derivedDataUsage = remeasured
		}
		await store.receive(\.derivedDataMeasurementFinished) {
			$0.isMeasuringDerivedData = false
		}
		#expect(deletedKinds.value == [.orphaned])
	}

	@Test("folders that could not be deleted are named in an alert")
	func reportsDerivedDataDeletionFailures() async {
		var initialState = SettingsReducer.State()
		initialState.deletingDerivedDataKind = .leftover
		let store = TestStore(initialState: initialState) {
			SettingsReducer()
		} withDependencies: {
			$0[DerivedDataUsageClient.self].measure = { .finished }
		}
		await store.send(.derivedDataDeletionFinished(DerivedDataDeletion(deletedFolders: 1, failures: ["“A” could not be removed."]))) {
			$0.deletingDerivedDataKind = nil
			$0.isMeasuringDerivedData = true
			$0.alert = AlertState {
				TextState("Some Folders Were Not Deleted")
			} actions: {
				ButtonState(role: .cancel) {
					TextState("OK")
				}
			} message: {
				TextState("“A” could not be removed.")
			}
		}
		await store.receive(\.derivedDataMeasurementFinished) {
			$0.isMeasuringDerivedData = false
		}
	}

	@Test("a kind with no folders offers nothing to delete")
	func ignoresDeletingAnEmptyKind() async {
		var initialState = SettingsReducer.State()
		initialState.derivedDataUsage = DerivedDataUsage(tallies: [.inUse: .init(folders: 1)], measuredFolders: 1, totalFolders: 1)
		let store = TestStore(initialState: initialState) {
			SettingsReducer()
		}
		await store.send(.deleteDerivedDataButtonTapped(.leftover))
	}

	// MARK: - Representative scalar setters

	@Test("clearGitHubToken empties the GitHub token")
	func clearGitHubToken() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setGitHubToken("ghp_abc")) {
			$0.$githubToken.withLock { $0 = "ghp_abc" }
		}
		await store.send(.clearGitHubToken) {
			$0.$githubToken.withLock { $0 = "" }
		}
	}

	@Test("setPeriodicRefreshInterval updates the shared interval")
	func setPeriodicRefreshInterval() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setPeriodicRefreshInterval(.thirtyMinutes)) {
			$0.$periodicRefreshInterval.withLock { $0 = .thirtyMinutes }
		}
	}

	@Test("setBranchNameRegex updates the shared regex")
	func setBranchNameRegex() async {
		let store = TestStore(initialState: SettingsReducer.State()) {
			SettingsReducer()
		}
		await store.send(.setBranchNameRegex("FOO-[0-9]+")) {
			$0.$branchNameRegex.withLock { $0 = "FOO-[0-9]+" }
		}
	}
}
