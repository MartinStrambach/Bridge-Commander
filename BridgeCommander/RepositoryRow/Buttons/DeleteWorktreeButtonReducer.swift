import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		let path: String
		var isRemoving: Bool = false
		var showingConfirmationSheet: Bool = false
		var forceRemoval: Bool = false
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
	}

	enum Action: BindableAction {
		case binding(BindingAction<State>)
		case showConfirmation
		case confirmRemoval
		case cancelRemoval
		case errorAlert(PresentationAction<ErrorAlert>)
		case didRemoveSuccessfully
		case didFailWithError(String)

		enum ErrorAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .showConfirmation:
				state.forceRemoval = false
				state.showingConfirmationSheet = true
				return .none

			case .confirmRemoval:
				state.showingConfirmationSheet = false
				state.isRemoving = true
				return .run { [name = state.name, path = state.path, force = state.forceRemoval] send in
					do {
						try await GitWorktreeRemover.removeWorktree(name: name, path: path, force: force)
						await send(.didRemoveSuccessfully)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
					}
				}

			case .cancelRemoval:
				state.showingConfirmationSheet = false
				state.forceRemoval = false
				return .none

			case .didRemoveSuccessfully:
				state.isRemoving = false
				state.forceRemoval = false
				return .none

			case let .didFailWithError(error):
				state.isRemoving = false
				state.forceRemoval = false
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

			case .binding:
				return .none
			}
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
	}
}
