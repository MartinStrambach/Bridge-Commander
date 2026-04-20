import ComposableArchitecture
import Foundation
import GitHosting
import ToolsIntegration

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

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .setYouTrackToken(token):
				state.$youtrackAuthToken.withLock { $0 = token }
				return .none

			case let .setGitHubToken(token):
				state.$githubToken.withLock { $0 = token }
				return .none

			case let .setGitLabToken(token):
				state.$gitlabToken.withLock { $0 = token }
				return .none

			case .clearGitHubToken:
				state.$githubToken.withLock { $0 = "" }
				return .none

			case .clearGitLabToken:
				state.$gitlabToken.withLock { $0 = "" }
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
