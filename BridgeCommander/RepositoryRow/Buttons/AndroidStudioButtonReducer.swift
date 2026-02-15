import ComposableArchitecture
import Foundation

@Reducer
struct AndroidStudioButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isOpening: Bool = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case openAndroidStudioButtonTapped
		case didOpenAndroidStudio
		case openFailed(String)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openAndroidStudioButtonTapped:
				state.isOpening = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await AndroidStudioLauncher.openInAndroidStudio(at: path)
						await send(.didOpenAndroidStudio)
					}
					catch {
						await send(.openFailed(error.localizedDescription))
					}
				}

			case .didOpenAndroidStudio:
				state.isOpening = false
				return .none

			case let .openFailed(errorMessage):
				state.isOpening = false
				state.alert = .okAlert(
					title: "Failed to Open Android Studio",
					message: errorMessage
				)
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
