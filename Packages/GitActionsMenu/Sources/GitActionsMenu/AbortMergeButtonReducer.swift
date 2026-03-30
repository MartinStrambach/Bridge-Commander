import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Abort Merge Button Reducer

@Reducer
public struct AbortMergeButtonReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		var isAbortingMerge = false
	}

	public enum Action: Equatable {
		case abortMergeTapped
		case abortMergeCompleted(success: Bool, error: String?)
	}

	public var body: some Reducer<State, Action> {
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
