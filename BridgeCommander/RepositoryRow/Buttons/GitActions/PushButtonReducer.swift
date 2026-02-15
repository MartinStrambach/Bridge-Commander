import ComposableArchitecture
import Foundation

// MARK: - Push Button Reducer

@Reducer
struct PushButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isPushing = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case pushTapped
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
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

			case let .pushCompleted(result, error):
				state.isPushing = false
				if let error {
					state.alert = .okAlert(title: "Git Operation Failed", message: error.localizedDescription)
				}
				else if let result {
					let message =
						if result.isUpToDate {
							"Everything is already up to date with the remote branch."
						}
						else {
							"Successfully pushed commits to remote branch."
						}

					state.alert = .okAlert(title: "Push Successful", message: message)
				}
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
