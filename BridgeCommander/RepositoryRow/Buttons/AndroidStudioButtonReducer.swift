import ComposableArchitecture
import Foundation

@Reducer
struct AndroidStudioButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isOpening: Bool = false
		@Shared(.mobileSubfolderPath)
		var mobileSubfolderPath = "ios/FlashScore"
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
				return .run { [path = state.repositoryPath, subfolder = state.mobileSubfolderPath] send in
					let targetPath = subfolder.isEmpty ? path : "\(path)/\(subfolder)"
					do {
						try await AndroidStudioLauncher.openInAndroidStudio(at: targetPath)
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
