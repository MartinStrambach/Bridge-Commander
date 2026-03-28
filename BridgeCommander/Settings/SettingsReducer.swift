import ComposableArchitecture
import Foundation

@Reducer
struct SettingsReducer {
	@ObservableState
	struct State: Equatable {
		@Shared(.youtrackAuthToken)
		var youtrackAuthToken = ""

		@Shared(.periodicRefreshInterval)
		var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Shared(.groupSettings)
		var groupSettings: [String: RepoGroupSettings] = [:]

		@Shared(.trackedRepoPaths)
		var trackedRepoPaths: [String] = []

		@Shared(.ticketIdRegex)
		var ticketIdRegex = "MOB-[0-9]+"

		@Shared(.branchNameRegex)
		var branchNameRegex = "[a-zA-Z]+-\\d+[_/]"

		@Shared(.openXcodeAfterGenerate)
		var openXcodeAfterGenerate = true

		@Shared(.deleteDerivedDataOnWorktreeDelete)
		var deleteDerivedDataOnWorktreeDelete = true

		@Shared(.tuistCacheType)
		var tuistCacheType = TuistCacheType.externalOnly

		@Shared(.terminalOpeningBehavior)
		var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

		@Shared(.claudeCodeOpeningBehavior)
		var claudeCodeOpeningBehavior = TerminalOpeningBehavior.newWindow

		@Shared(.androidStudioPath)
		var androidStudioPath = "/Applications/Android Studio.app/Contents/MacOS/studio"

		@Shared(.worktreeBasePath)
		var worktreeBasePath = "../worktrees"

		@Shared(.terminalColorTheme)
		var terminalColorTheme = TerminalColorTheme.basicDark

		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action {
		case setYouTrackToken(String)
		case setPeriodicRefreshInterval(PeriodicRefreshInterval)
		case setGroupSupportsIOS(groupId: String, value: Bool)
		case setGroupSupportsAndroid(groupId: String, value: Bool)
		case setGroupMobileSubfolderPath(groupId: String, path: String)
		case setGroupIOSSubfolderPath(groupId: String, path: String)
		case setTicketIdRegex(String)
		case setBranchNameRegex(String)
		case setOpenXcodeAfterGenerate(Bool)
		case setDeleteDerivedDataOnWorktreeDelete(Bool)
		case setTuistCacheType(TuistCacheType)
		case setTerminalOpeningBehavior(TerminalOpeningBehavior)
		case setClaudeCodeOpeningBehavior(TerminalOpeningBehavior)
		case setAndroidStudioPath(String)
		case setWorktreeBasePath(String)
		case setTerminalColorTheme(TerminalColorTheme)
		case clearTokenButtonTapped
		case alert(PresentationAction<Alert>)

		@CasePathable
		enum Alert {
			case confirmClearToken
		}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .setYouTrackToken(token):
				state.$youtrackAuthToken.withLock { $0 = token }
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

			case let .setTicketIdRegex(regex):
				state.$ticketIdRegex.withLock { $0 = regex }
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
