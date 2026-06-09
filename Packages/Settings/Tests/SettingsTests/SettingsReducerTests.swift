import ComposableArchitecture
import Foundation
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
