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
		case clearing

		var progressText: String {
			switch self {
			case .stashing: "Stashing..."
			case .applying: "Applying stash..."
			case .popping: "Popping stash..."
			case .clearing: "Clearing stash..."
			}
		}

		var progressHelpText: String {
			switch self {
			case .stashing: "Stashing changes..."
			case .applying: "Restoring stashed changes..."
			case .popping: "Restoring stashed changes and dropping the stash..."
			case .clearing: "Dropping the stash without restoring it..."
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
		@Presents
		var confirmationDialog: ConfirmationDialogState<Action.ConfirmAction>?

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
		case stashClearTapped
		case confirmationDialog(PresentationAction<ConfirmAction>)
		case stashCompleted(success: Bool, error: String?)
		case stashApplyCompleted(success: Bool, error: String?)
		case stashPopCompleted(success: Bool, error: String?)
		case stashClearCompleted(success: Bool, error: String?)
		case checkStashStatus
		case didFindStash(GitStashEntry?)

		public enum ConfirmAction: Equatable {
			case confirmClear
		}
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

			case .stashClearTapped:
				// Clearing throws the stashed work away without ever putting it back in
				// the working tree, so unlike apply and pop it asks first.
				guard let stash = state.stash else {
					return .none
				}

				state.confirmationDialog = Self.clearConfirmation(for: stash)
				return .none

			case .confirmationDialog(.presented(.confirmClear)):
				guard let reference = state.stash?.reference else {
					return .none
				}

				state.operation = .clearing
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitStashHelper.stashDrop(at: path, reference: reference)
						await send(.stashClearCompleted(success: true, error: nil))
					}
					catch {
						await send(.stashClearCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .confirmationDialog:
				return .none

			case .stashApplyCompleted,
			     .stashClearCompleted,
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
		.ifLet(\.$confirmationDialog, action: \.confirmationDialog)
	}

	// MARK: - Confirmation dialog

	static func clearConfirmation(for stash: GitStashEntry) -> ConfirmationDialogState<Action.ConfirmAction> {
		ConfirmationDialogState {
			TextState("Clear stash?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmClear) {
				TextState("Clear Stash")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			// Name the entry: the list is shared by every worktree, so it pays to show
			// exactly which stash is about to go.
			TextState("This permanently deletes \(stash.reference) — “\(stash.message)” — without restoring it.")
		}
	}
}
