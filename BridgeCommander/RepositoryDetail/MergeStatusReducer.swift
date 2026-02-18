import ComposableArchitecture
import Foundation

@Reducer
struct MergeStatus {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isMergeInProgress = false
	}

	enum Action: Sendable {
		case finishMergeButtonTapped
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
				return .run { [path = state.repositoryPath] send in
					await send(.delegate(.operationCompleted(Result { try await GitMergeHelper.finishMerge(at: path) })))
				}

			case .delegate:
				return .none
			}
		}
	}
}
