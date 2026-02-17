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
		var alert: GitAlert?
	}

	enum Action: Equatable {
		case stashTapped
		case stashPopTapped
		case stashCompleted(success: Bool, error: String?)
		case stashPopCompleted(success: Bool, error: String?)
		case checkStashStatus
		case didCheckStashStatus(hasStash: Bool)
		case updateHasChanges(Bool)
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
					catch {
						await send(.stashCompleted(success: false, error: error.localizedDescription))
					}
				}

			case let .stashCompleted(success, error):
				state.isProcessing = false
				if let error {
					state.alert = GitAlert(title: "Stash Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlert(
						title: "Stash Successful",
						message: "Changes have been stashed successfully.",
						isError: false
					)
					return .send(.checkStashStatus)
				}
				return .none

			case .stashPopTapped:
				state.isProcessing = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stashPop(at: path)
						await send(.stashPopCompleted(success: true, error: nil))
					}
					catch {
						await send(.stashPopCompleted(success: false, error: error.localizedDescription))
					}
				}

			case let .stashPopCompleted(success, error):
				state.isProcessing = false
				if let error {
					state.alert = GitAlert(title: "Stash Pop Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlert(
						title: "Stash Pop Successful",
						message: "Stashed changes have been restored successfully.",
						isError: false
					)
					return .send(.checkStashStatus)
				}
				return .none

			case .checkStashStatus:
				return .run { [path = state.repositoryPath] send in
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

			}
		}
	}
}
