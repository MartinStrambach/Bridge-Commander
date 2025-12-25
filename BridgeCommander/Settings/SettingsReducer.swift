import ComposableArchitecture
import Foundation

@Reducer
struct SettingsReducer {
	@ObservableState
	struct State: Equatable {
		@Shared(.appStorage("youtrackAuthToken"))
		var youtrackAuthToken = ""

		@Shared(.appStorage("periodicRefreshInterval"))
		var periodicRefreshInterval = PeriodicRefreshInterval.fiveMinutes

		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Sendable {
		case setYouTrackToken(String)
		case setPeriodicRefreshInterval(PeriodicRefreshInterval)
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
