import ComposableArchitecture
import Foundation

@Reducer
struct DeleteWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		let path: String
		var isRemoving: Bool = false
		@Shared(.deleteDerivedDataOnWorktreeDelete)
		var deleteDerivedDataOnWorktreeDelete = true
		@Presents
		var confirmationSheet: DeleteWorktreeConfirmationReducer.State?
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
		@Presents
		var derivedDataWarningAlert: AlertState<Action.DerivedDataWarningAlert>?
	}

	enum Action {
		case showConfirmation
		case confirmationSheet(PresentationAction<DeleteWorktreeConfirmationReducer.Action>)
		case errorAlert(PresentationAction<ErrorAlert>)
		case derivedDataWarningAlert(PresentationAction<DerivedDataWarningAlert>)
		case didRemoveSuccessfully
		case didRemoveSuccessfullyWithDerivedDataWarning(String)
		case didFailWithError(String)

		enum ErrorAlert: Equatable {}
		enum DerivedDataWarningAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .showConfirmation:
				state.confirmationSheet = DeleteWorktreeConfirmationReducer.State(name: state.name)
				return .none

			case let .confirmationSheet(.presented(.confirmTapped(forceRemoval: force))):
				state.confirmationSheet = nil
				state.isRemoving = true
				return .run { [
					name = state.name,
					path = state.path,
					deleteDerivedData = state.deleteDerivedDataOnWorktreeDelete
				] send in
					do {
						try await GitWorktreeRemover.removeWorktree(name: name, path: path, force: force)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
						return
					}
					if deleteDerivedData {
						do {
							try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: path)
						}
						catch {
							await send(.didRemoveSuccessfullyWithDerivedDataWarning(error.localizedDescription))
							return
						}
					}
					await send(.didRemoveSuccessfully)
				}

			case .confirmationSheet(.presented(.cancelTapped)):
				state.confirmationSheet = nil
				return .none

			case .confirmationSheet:
				return .none

			case .didRemoveSuccessfully:
				state.isRemoving = false
				return .none

			case let .didRemoveSuccessfullyWithDerivedDataWarning(message):
				state.isRemoving = false
				state.derivedDataWarningAlert = AlertState {
					TextState("Worktree Removed")
				} actions: {
					ButtonState(role: .cancel) { TextState("OK") }
				} message: {
					TextState("Worktree was removed successfully, but DerivedData cleanup failed: \(message)")
				}
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

			case .derivedDataWarningAlert:
				return .none
			}
		}
		.ifLet(\.$confirmationSheet, action: \.confirmationSheet) {
			DeleteWorktreeConfirmationReducer()
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
		.ifLet(\.$derivedDataWarningAlert, action: \.derivedDataWarningAlert)
	}
}
