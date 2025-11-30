import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		let path: String
		var isRemoving: Bool = false
		@Presents
		var confirmationAlert: AlertState<Action.ConfirmationAlert>?
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showConfirmation
		case confirmationAlert(PresentationAction<ConfirmationAlert>)
		case errorAlert(PresentationAction<ErrorAlert>)
		case didRemoveSuccessfully
		case didFailWithError(String)

		enum ConfirmationAlert: Equatable {
			case confirmRemoval
		}

		enum ErrorAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showConfirmation:
				let worktreeName = state.name
				state.confirmationAlert = AlertState {
					TextState("Remove Worktree")
				} actions: {
					ButtonState(role: .cancel) {
						TextState("Cancel")
					}
					ButtonState(role: .destructive, action: .confirmRemoval) {
						TextState("Remove")
					}
				} message: {
					TextState("Are you sure you want to remove this worktree?\n\n\(worktreeName)")
				}
				return .none

			case .confirmationAlert(.presented(.confirmRemoval)):
				state.confirmationAlert = nil
				state.isRemoving = true
				return .run { [name = state.name, path = state.path] send in
					do {
						try await GitWorktreeRemover.removeWorktree(name: name, path: path)
						await send(.didRemoveSuccessfully)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case .confirmationAlert:
				return .none

			case .didRemoveSuccessfully:
				state.isRemoving = false
				return .none

			case let .didFailWithError(error):
				state.isRemoving = false
				state.errorAlert = AlertState {
					TextState("Removal Error")
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
		.ifLet(\.$confirmationAlert, action: \.confirmationAlert)
		.ifLet(\.$errorAlert, action: \.errorAlert)
	}
}
