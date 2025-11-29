import ComposableArchitecture
import Foundation

@Reducer
struct CreateWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isCreating: Bool = false
		var showCreateDialog: Bool = false
		var branchName: String = ""
		var creationError: String?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showDialog
		case cancelCreation
		case confirmCreation
		case didCreateSuccessfully
		case didFailWithError(String)
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showDialog:
				state.showCreateDialog = true
				state.branchName = ""
				state.creationError = nil
				return .none

			case .cancelCreation:
				state.showCreateDialog = false
				state.branchName = ""
				return .none

			case .confirmCreation:
				guard !state.branchName.isEmpty else {
					return .none
				}

				state.showCreateDialog = false
				state.isCreating = true
				return .run { [branchName = state.branchName, path = state.repositoryPath] send in
					do {
						try await GitWorktreeCreator.createWorktree(
							branchName: branchName,
							repositoryPath: path
						)
						await send(.didCreateSuccessfully)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case .didCreateSuccessfully:
				state.isCreating = false
				state.branchName = ""
				return .none

			case let .didFailWithError(error):
				state.isCreating = false
				state.creationError = error
				return .none

			default:
				return .none
			}
		}
	}
}
