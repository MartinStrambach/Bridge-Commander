import ComposableArchitecture
import Foundation

// MARK: - Abort Merge Button Reducer

@Reducer
struct AbortMergeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isAbortingMerge = false
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

			case .abortMergeCompleted:
				state.isAbortingMerge = false
				return .none
			}
		}
	}
}
