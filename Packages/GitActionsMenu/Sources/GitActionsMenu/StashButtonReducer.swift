import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Stash Button Reducer

@Reducer
public struct StashButtonReducer {
	/// The git command currently running, which also names the progress the menu shows.
	public enum Operation: Equatable {
		case stashing
		case applying
		case popping

		var progressText: String {
			switch self {
			case .stashing: "Stashing..."
			case .applying,
			     .popping: "Applying stash..."
			}
		}

		var progressHelpText: String {
			switch self {
			case .stashing: "Stashing changes..."
			case .applying: "Restoring stashed changes..."
			case .popping: "Restoring stashed changes and dropping the stash..."
			}
		}
	}

	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		/// The branch whose stash this button acts on. Kept in sync by
		/// `GitActionsMenuReducer.State.setCurrentBranch` — the row only knows the real
		/// branch once its status fetch lands, and a stale value here means the stash
		/// lookup silently matches nothing.
		var currentBranch: String
		/// The newest stash on `currentBranch`, as of the last check.
		var stash: GitStashEntry?
		var operation: Operation?

		public var hasChanges = false

		public var hasStash: Bool {
			stash != nil
		}

		public var isProcessing: Bool {
			operation != nil
		}

		init(
			repositoryPath: String,
			currentBranch: String,
			stash: GitStashEntry? = nil,
			operation: Operation? = nil
		) {
			self.repositoryPath = repositoryPath
			self.currentBranch = currentBranch
			self.stash = stash
			self.operation = operation
		}
	}

	public enum Action: Equatable {
		case stashTapped
		case stashApplyTapped
		case stashPopTapped
		case stashCompleted(success: Bool, error: String?)
		case stashApplyCompleted(success: Bool, error: String?)
		case stashPopCompleted(success: Bool, error: String?)
		case checkStashStatus
		case didFindStash(GitStashEntry?)
	}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .stashTapped:
				state.operation = .stashing
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stash(at: path)
						await send(.stashCompleted(success: true, error: nil))
					}
					catch {
						await send(.stashCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .stashApplyTapped:
				guard let reference = state.stash?.reference else {
					return .none
				}

				state.operation = .applying
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stashApply(at: path, reference: reference)
						await send(.stashApplyCompleted(success: true, error: nil))
					}
					catch {
						await send(.stashApplyCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .stashPopTapped:
				guard let reference = state.stash?.reference else {
					return .none
				}

				state.operation = .popping
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stashPop(at: path, reference: reference)
						await send(.stashPopCompleted(success: true, error: nil))
					}
					catch {
						await send(.stashPopCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .stashApplyCompleted,
			     .stashCompleted,
			     .stashPopCompleted:
				state.operation = nil
				return .none

			case .checkStashStatus:
				return .run { [path = state.repositoryPath, currentBranch = state.currentBranch] send in
					await send(.didFindStash(GitStashHelper.findStash(at: path, branch: currentBranch)))
				}

			case let .didFindStash(stash):
				state.stash = stash
				return .none
			}
		}
	}
}
