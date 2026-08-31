import ComposableArchitecture
import Foundation
import GitHosting
import ToolsIntegration

/// Outcome of a "Test Connection" run against a hosting provider token.
public enum TokenTestState: Equatable, Sendable {
	case idle
	case testing
	case success(username: String)
	case failure(message: String)
}

@Reducer
public struct SettingsReducer {
	@ObservableState
	public struct State: Equatable {
		@Shared(.youtrackAuthToken)
		public var youtrackAuthToken = ""

		@Shared(.githubToken)
		public var githubToken = ""

		@Shared(.gitlabToken)
		public var gitlabToken = ""

		@Shared(.periodicRefreshInterval)
		public var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Shared(.groupSettings)
		public var groupSettings: [String: RepoGroupSettings] = [:]

		@Shared(.trackedRepoPaths)
		public var trackedRepoPaths: [String] = []

		@Shared(.branchNameRegex)
		public var branchNameRegex = "[a-zA-Z]+-\\d+[_/]"

		@Shared(.openXcodeAfterGenerate)
		public var openXcodeAfterGenerate = true

		@Shared(.deleteDerivedDataOnWorktreeDelete)
		public var deleteDerivedDataOnWorktreeDelete = true

		@Shared(.tuistCacheType)
		public var tuistCacheType = TuistCacheType.externalOnly

		@Shared(.terminalApp)
		public var terminalApp = TerminalApp.systemTerminal

		@Shared(.terminalOpeningBehavior)
		public var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

		@Shared(.claudeCodeOpeningBehavior)
		public var claudeCodeOpeningBehavior = TerminalOpeningBehavior.newWindow

		@Shared(.androidStudioPath)
		public var androidStudioPath = "/Applications/Android Studio.app/Contents/MacOS/studio"

		@Shared(.misePath)
		public var misePath = NSHomeDirectory() + "/.local/bin/mise"

		@Shared(.tuistRunMode)
		public var tuistRunMode = TuistRunMode.mise

		@Shared(.worktreeBasePath)
		public var worktreeBasePath = "../worktrees"

		@Shared(.terminalColorTheme)
		public var terminalColorTheme = TerminalColorTheme.basicDark

		public var githubTokenTest = TokenTestState.idle
		public var gitlabTokenTest = TokenTestState.idle

		@Presents
		public var alert: AlertState<Action.Alert>?

		public init() {}
	}

	public enum Action {
		case setYouTrackToken(String)
		case setGitHubToken(String)
		case setGitLabToken(String)
		case clearGitHubToken
		case clearGitLabToken
		case testGitHubTokenButtonTapped
		case testGitLabTokenButtonTapped
		case gitHubTokenTestFinished(TokenTestState)
		case gitLabTokenTestFinished(TokenTestState)
		case setPeriodicRefreshInterval(PeriodicRefreshInterval)
		case setGroupSupportsIOS(groupId: String, value: Bool)
		case setGroupSupportsAndroid(groupId: String, value: Bool)
		case setGroupMobileSubfolderPath(groupId: String, path: String)
		case setGroupIOSSubfolderPath(groupId: String, path: String)
		case setGroupSupportsTuist(groupId: String, value: Bool)
		case setGroupTicketIdRegex(groupId: String, regex: String)
		case setGroupXcodeFilePreference(groupId: String, preference: XcodeFilePreference)
		case setGroupWorktreeCopyPaths(groupId: String, value: [String])
		case setGroupSupportsWeb(groupId: String, value: Bool)
		case setGroupWebIndexPath(groupId: String, path: String)
		case setGroupDefaultBranch(groupId: String, value: String)
		case setBranchNameRegex(String)
		case setOpenXcodeAfterGenerate(Bool)
		case setDeleteDerivedDataOnWorktreeDelete(Bool)
		case setTuistCacheType(TuistCacheType)
		case setTerminalApp(TerminalApp)
		case setTerminalOpeningBehavior(TerminalOpeningBehavior)
		case setClaudeCodeOpeningBehavior(TerminalOpeningBehavior)
		case setAndroidStudioPath(String)
		case setWorktreeBasePath(String)
		case setMisePath(String)
		case setTuistRunMode(TuistRunMode)
		case setTerminalColorTheme(TerminalColorTheme)
		case clearTokenButtonTapped
		case alert(PresentationAction<Alert>)

		@CasePathable
		public enum Alert {
			case confirmClearToken
		}
	}

	@Dependency(TokenVerificationClient.self)
	private var tokenVerification

	public init() {}

	/// Runs a verification call and condenses its result into displayable state.
	private static func tokenTestOutcome(
		provider: PullRequestProvider,
		_ verify: @Sendable () async throws -> String
	) async -> TokenTestState {
		do {
			return try await .success(username: verify())
		}
		catch {
			return .failure(message: tokenTestFailureMessage(for: error, provider: provider))
		}
	}

	private static func tokenTestFailureMessage(for error: Error, provider: PullRequestProvider) -> String {
		switch error {
		case GitHostingError.missingToken:
			"Enter a token first."

		case GitHostingError.httpFailure(statusCode: 401):
			"HTTP 401 — the token is invalid, revoked, or expired."

		case GitHostingError.httpFailure(statusCode: 403):
			"HTTP 403 — the token lacks API access; check its scopes."

		case let GitHostingError.httpFailure(statusCode):
			"HTTP \(statusCode)."

		case GitHostingError.unauthenticated where provider == .gitlab:
			"GitLab accepted the request but returned no user. Fine-grained tokens cannot use the GraphQL API this app relies on — use a personal, project, or group token with the read_api scope."

		case GitHostingError.unauthenticated:
			"GitHub accepted the request but returned no user — the token likely cannot call the GraphQL API; check its type and permissions."

		default:
			error.localizedDescription
		}
	}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			// Tokens are trimmed because a paste often carries a trailing newline, which
			// corrupts the Bearer header and makes every request fail with a silent 401.
			case let .setYouTrackToken(token):
				state.$youtrackAuthToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				return .none

			case let .setGitHubToken(token):
				state.$githubToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				// A verdict describes the token it was run against — a different token
				// must not inherit it.
				state.githubTokenTest = .idle
				return .none

			case let .setGitLabToken(token):
				state.$gitlabToken.withLock { $0 = token.trimmingCharacters(in: .whitespacesAndNewlines) }
				state.gitlabTokenTest = .idle
				return .none

			case .clearGitHubToken:
				state.$githubToken.withLock { $0 = "" }
				state.githubTokenTest = .idle
				return .none

			case .clearGitLabToken:
				state.$gitlabToken.withLock { $0 = "" }
				state.gitlabTokenTest = .idle
				return .none

			case .testGitHubTokenButtonTapped:
				state.githubTokenTest = .testing
				return .run { [token = state.githubToken, tokenVerification] send in
					await send(.gitHubTokenTestFinished(Self.tokenTestOutcome(provider: .github) {
						try await tokenVerification.verifyGitHubToken(token)
					}))
				}

			case .testGitLabTokenButtonTapped:
				state.gitlabTokenTest = .testing
				return .run { [token = state.gitlabToken, tokenVerification] send in
					await send(.gitLabTokenTestFinished(Self.tokenTestOutcome(provider: .gitlab) {
						try await tokenVerification.verifyGitLabToken(token)
					}))
				}

			case let .gitHubTokenTestFinished(outcome):
				state.githubTokenTest = outcome
				return .none

			case let .gitLabTokenTestFinished(outcome):
				state.gitlabTokenTest = outcome
				return .none

			case let .setPeriodicRefreshInterval(interval):
				state.$periodicRefreshInterval.withLock { $0 = interval }
				return .none

			case let .setGroupSupportsIOS(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsIOS = value }
				return .none

			case let .setGroupSupportsAndroid(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsAndroid = value }
				return .none

			case let .setGroupMobileSubfolderPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].mobileSubfolderPath = path }
				return .none

			case let .setGroupIOSSubfolderPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].iosSubfolderPath = path }
				return .none

			case let .setGroupSupportsTuist(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsTuist = value }
				return .none

			case let .setGroupTicketIdRegex(groupId, regex):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].ticketIdRegex = regex }
				return .none

			case let .setGroupXcodeFilePreference(groupId, preference):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].xcodeFilePreference = preference }
				return .none

			case let .setGroupWorktreeCopyPaths(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].worktreeCopyPaths = value }
				return .none

			case let .setGroupSupportsWeb(groupId, value):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].supportsWeb = value }
				return .none

			case let .setGroupWebIndexPath(groupId, path):
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].webIndexPath = path }
				return .none

			case let .setGroupDefaultBranch(groupId, value):
				// Trim so a whitespace-only entry is stored as empty (= master/main fallback),
				// keeping every downstream consumer (resolver, merge, alerts) consistent.
				let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
				state.$groupSettings.withLock { $0[groupId, default: RepoGroupSettings()].defaultBranch = trimmed }
				return .none

			case let .setBranchNameRegex(regex):
				state.$branchNameRegex.withLock { $0 = regex }
				return .none

			case let .setOpenXcodeAfterGenerate(shouldOpen):
				state.$openXcodeAfterGenerate.withLock { $0 = shouldOpen }
				return .none

			case let .setDeleteDerivedDataOnWorktreeDelete(value):
				state.$deleteDerivedDataOnWorktreeDelete.withLock { $0 = value }
				return .none

			case let .setTuistCacheType(cacheType):
				state.$tuistCacheType.withLock { $0 = cacheType }
				return .none

			case let .setTerminalApp(app):
				state.$terminalApp.withLock { $0 = app }
				return .none

			case let .setTerminalOpeningBehavior(behavior):
				state.$terminalOpeningBehavior.withLock { $0 = behavior }
				return .none

			case let .setClaudeCodeOpeningBehavior(behavior):
				state.$claudeCodeOpeningBehavior.withLock { $0 = behavior }
				return .none

			case let .setAndroidStudioPath(path):
				state.$androidStudioPath.withLock { $0 = path }
				return .none

			case let .setWorktreeBasePath(path):
				state.$worktreeBasePath.withLock { $0 = path }
				return .none

			case let .setMisePath(path):
				state.$misePath.withLock { $0 = path }
				return .none

			case let .setTuistRunMode(mode):
				state.$tuistRunMode.withLock { $0 = mode }
				return .none

			case let .setTerminalColorTheme(theme):
				state.$terminalColorTheme.withLock { $0 = theme }
				return .none

			case .clearTokenButtonTapped:
				state.alert = AlertState {
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
				return .none

			case .alert(.presented(.confirmClearToken)):
				state.$youtrackAuthToken.withLock { $0 = "" }
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
