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

		@Shared(.iosSubfolderPath)
		var iosSubfolderPath = "ios/FlashScore"

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

		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Sendable {
		case setYouTrackToken(String)
		case setPeriodicRefreshInterval(PeriodicRefreshInterval)
		case setIosSubfolderPath(String)
		case setTicketIdRegex(String)
		case setBranchNameRegex(String)
		case setOpenXcodeAfterGenerate(Bool)
		case setDeleteDerivedDataOnWorktreeDelete(Bool)
		case setTuistCacheType(TuistCacheType)
		case setTerminalOpeningBehavior(TerminalOpeningBehavior)
		case setClaudeCodeOpeningBehavior(TerminalOpeningBehavior)
		case setAndroidStudioPath(String)
		case clearTokenButtonTapped
		case alert(PresentationAction<Alert>)

		@CasePathable
		enum Alert: Sendable {
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

			case let .setIosSubfolderPath(path):
				state.$iosSubfolderPath.withLock { $0 = path }
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
