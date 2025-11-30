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
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showDialog
		case cancelCreation
		case confirmCreation
		case errorAlert(PresentationAction<ErrorAlert>)
		case didCreateSuccessfully
		case didFailWithError(String)

		enum ErrorAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showDialog:
				state.showCreateDialog = true
				state.branchName = ""
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
				state.errorAlert = AlertState {
					TextState("Creation Error")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(error)
				}
				return .none

			case .errorAlert:
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
	}
}
