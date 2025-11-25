import ComposableArchitecture
import Foundation

@Reducer
struct AndroidStudioButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isOpening: Bool = false
		var errorMessage: String? = nil
	}

	enum Action: Equatable {
		case openAndroidStudioButtonTapped
		case didOpenAndroidStudio
		case openFailed(String)
		case dismissError
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
					} catch {
						await send(.openFailed(error.localizedDescription))
					}
				}

			case .didOpenAndroidStudio:
				state.isOpening = false
				return .none

			case let .openFailed(errorMessage):
				state.isOpening = false
				state.errorMessage = errorMessage
				return .none

			case .dismissError:
				state.errorMessage = nil
				return .none
			}
		}
	}
}
