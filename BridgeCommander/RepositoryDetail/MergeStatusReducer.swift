import ComposableArchitecture
import Foundation

@Reducer
struct MergeStatus {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isMergeInProgress = false
		var isLoading = false
	}

	enum Action: Sendable {
		case finishMergeButtonTapped
		case finishMergeCompleted(Result<Void, Error>)
		case loadStatusResponse(Bool)
		case delegate(Delegate)

		enum Delegate: Sendable {
			case operationCompleted(Result<Void, Error>)
		}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .loadStatusResponse(isMergeInProgress):
				state.isMergeInProgress = isMergeInProgress
				return .none

			case .finishMergeButtonTapped:
				state.isLoading = true
				return .run { [path = state.repositoryPath] send in
					await send(.finishMergeCompleted(Result { try await GitMergeHelper.finishMerge(at: path) }))
				}

			case let .finishMergeCompleted(result):
				state.isLoading = false
				return .send(.delegate(.operationCompleted(result)))

			case .delegate:
				return .none
			}
		}
	}
}
