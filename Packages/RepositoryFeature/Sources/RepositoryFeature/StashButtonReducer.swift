import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Stash Button Reducer

@Reducer
struct StashButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		let currentBranch: String
		var hasStash = false
		var hasChanges = false
		var isProcessing = false
	}

	enum Action: Equatable {
		case stashTapped
		case stashPopTapped
		case stashCompleted(success: Bool, error: String?)
		case stashPopCompleted(success: Bool, error: String?)
		case checkStashStatus
		case didCheckStashStatus(hasStash: Bool)
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

			case .stashCompleted,
			     .stashPopCompleted:
				state.isProcessing = false
				return .none

			case .checkStashStatus:
				return .run { [path = state.repositoryPath, currentBranch = state.currentBranch] send in
					let hasStash = await GitStashHelper.checkHasStashOnBranch(at: path, branch: currentBranch)
					await send(.didCheckStashStatus(hasStash: hasStash))
				}

			case let .didCheckStashStatus(hasStash):
				state.hasStash = hasStash
				return .none
			}
		}
	}
}
