import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isRemoving: Bool = false
		var showRemoveConfirmation: Bool = false
		var removalError: String?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showConfirmation
		case cancelRemoval
		case confirmRemoval
		case didRemoveSuccessfully
		case didFailWithError(String)
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showConfirmation:
				state.showRemoveConfirmation = true
				return .none

			case .cancelRemoval:
				state.showRemoveConfirmation = false
				return .none

			case .confirmRemoval:
				state.showRemoveConfirmation = false
				state.isRemoving = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitWorktreeRemover.removeWorktree(at: path)
						await send(.didRemoveSuccessfully)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case .didRemoveSuccessfully:
				state.isRemoving = false
				return .none

			case let .didFailWithError(error):
				state.isRemoving = false
				state.removalError = error
				return .none

			default:
				return .none
			}
		}
	}
}
