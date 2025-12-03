import ComposableArchitecture
import Foundation

// MARK: - Abort Merge Button Reducer

@Reducer
struct AbortMergeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isAbortingMerge = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case abortMergeTapped
		case abortMergeCompleted(success: Bool, error: String?)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .abortMergeTapped:
				state.isAbortingMerge = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitAbortMergeHelper.abortMerge(at: path)
						await send(.abortMergeCompleted(success: true, error: nil))
					}
					catch {
						await send(.abortMergeCompleted(success: false, error: error.localizedDescription))
					}
				}

			case let .abortMergeCompleted(success, error):
				state.isAbortingMerge = false
				if let error {
					state.alert = AlertState {
						TextState("Abort Merge Failed")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(error)
					}
				}
				else if success {
					state.alert = AlertState {
						TextState("Merge Aborted")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState("The merge has been successfully aborted.")
					}
				}
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
