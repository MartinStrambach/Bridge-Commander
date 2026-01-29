import ComposableArchitecture
import Foundation

// MARK: - Stash Button Reducer

@Reducer
struct StashButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var hasStash = false
		var hasChanges = false
		var isProcessing = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case stashTapped
		case stashPopTapped
		case stashCompleted(success: Bool, error: String?)
		case stashPopCompleted(success: Bool, error: String?)
		case checkStashStatus
		case didCheckStashStatus(hasStash: Bool)
		case updateHasChanges(Bool)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .stashTapped:
				state.isProcessing = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stash(at: path)
						await send(.stashCompleted(success: true, error: nil))
					}
					catch let error as GitStashHelper.StashError {
						let errorMessage = switch error {
						case let .stashFailed(msg):
							msg
						default:
							"Unknown error"
						}
						await send(.stashCompleted(success: false, error: errorMessage))
					}
					catch {
						await send(.stashCompleted(success: false, error: error.localizedDescription))
					}
				}

			case let .stashCompleted(success, error):
				state.isProcessing = false
				if success {
					state.alert = AlertState {
						TextState("Stash Successful")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState("Changes have been stashed successfully.")
					}
					return .send(.checkStashStatus)
				}
				else {
					state.alert = AlertState {
						TextState("Stash Failed")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(error ?? "Unknown error occurred")
					}
					return .none
				}

			case .stashPopTapped:
				state.isProcessing = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stashPop(at: path)
						await send(.stashPopCompleted(success: true, error: nil))
					}
					catch let error as GitStashHelper.StashError {
						let errorMessage = switch error {
						case let .stashPopFailed(msg):
							msg
						default:
							"Unknown error"
						}
						await send(.stashPopCompleted(success: false, error: errorMessage))
					}
					catch {
						await send(.stashPopCompleted(success: false, error: error.localizedDescription))
					}
				}

			case let .stashPopCompleted(success, error):
				state.isProcessing = false
				if success {
					state.alert = AlertState {
						TextState("Stash Pop Successful")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState("Stashed changes have been restored successfully.")
					}
					return .send(.checkStashStatus)
				}
				else {
					state.alert = AlertState {
						TextState("Stash Pop Failed")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(error ?? "Unknown error occurred")
					}
					return .none
				}

			case .checkStashStatus:
				return .run { [path = state.repositoryPath] send in
					// First get the current branch
					let currentBranch = await GitStashHelper.getCurrentBranch(at: path)
					let hasStash = await GitStashHelper.checkHasStashOnBranch(at: path, branch: currentBranch)
					await send(.didCheckStashStatus(hasStash: hasStash))
				}

			case let .didCheckStashStatus(hasStash):
				state.hasStash = hasStash
				return .none

			case let .updateHasChanges(hasChanges):
				state.hasChanges = hasChanges
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
