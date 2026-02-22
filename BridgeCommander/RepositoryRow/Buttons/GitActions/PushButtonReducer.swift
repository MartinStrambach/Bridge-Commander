import ComposableArchitecture
import Foundation

// MARK: - Push Button Reducer

@Reducer
struct PushButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isPushing = false
	}

	enum Action: Equatable {
		case pushTapped
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .pushTapped:
				state.isPushing = true
				return .run { [path = state.repositoryPath] send in
					do {
						let result = try await GitPushHelper.push(at: path)
						await send(.pushCompleted(result: result, error: nil))
					}
					catch let error as GitError {
						await send(.pushCompleted(result: nil, error: error))
					}
					catch {
						print("Unexpected error during push: \(error)")
						await send(.pushCompleted(result: nil, error: nil))
					}
				}

			case .pushCompleted:
				state.isPushing = false
				return .none
			}
		}
	}
}
