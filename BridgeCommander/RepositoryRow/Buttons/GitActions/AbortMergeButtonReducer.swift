import ComposableArchitecture
import Foundation

// MARK: - Abort Merge Button Reducer

@Reducer
struct AbortMergeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isAbortingMerge = false
		var alert: GitAlert?
	}

	enum Action: Equatable {
		case abortMergeTapped
		case abortMergeCompleted(success: Bool, error: String?)
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
					state.alert = GitAlert(title: "Abort Merge Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlert(
						title: "Merge Aborted",
						message: "The merge has been successfully aborted.",
						isError: false
					)
				}
				return .none

			}
		}
	}
}
