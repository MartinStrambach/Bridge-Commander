import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Discard Button Reducer

@Reducer
public struct DiscardButtonReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		/// "Discard Tracked Changes" is shown when there are tracked modifications.
		public var hasTrackedChanges = false
		/// "Discard All Changes" is shown when there are untracked files to clean.
		public var hasUntrackedFiles = false
		var isProcessing = false
		@Presents var confirmationDialog: ConfirmationDialogState<Action.ConfirmAction>?

		public init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}
	}

	public enum Action: Equatable {
		case discardTrackedTapped
		case discardAllTapped
		case confirmationDialog(PresentationAction<ConfirmAction>)
		case discardCompleted(success: Bool, error: String?)

		public enum ConfirmAction: Equatable {
			case confirmTracked
			case confirmAll
		}
	}

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .discardTrackedTapped:
				state.confirmationDialog = Self.trackedConfirmation
				return .none

			case .discardAllTapped:
				state.confirmationDialog = Self.allConfirmation
				return .none

			case .confirmationDialog(.presented(.confirmTracked)):
				state.isProcessing = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitDiscardHelper.discardTracked(at: path)
						await send(.discardCompleted(success: true, error: nil))
					}
					catch {
						await send(.discardCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .confirmationDialog(.presented(.confirmAll)):
				state.isProcessing = true
				return .run { [path = state.repositoryPath] send in
					do {
						try await GitDiscardHelper.discardAll(at: path)
						await send(.discardCompleted(success: true, error: nil))
					}
					catch {
						await send(.discardCompleted(success: false, error: error.localizedDescription))
					}
				}

			case .confirmationDialog:
				return .none

			case .discardCompleted:
				state.isProcessing = false
				return .none
			}
		}
		.ifLet(\.$confirmationDialog, action: \.confirmationDialog)
	}

	// MARK: - Confirmation dialogs

	static var trackedConfirmation: ConfirmationDialogState<Action.ConfirmAction> {
		ConfirmationDialogState {
			TextState("Discard tracked changes?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmTracked) {
				TextState("Discard Tracked Changes")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("This reverts all staged and unstaged changes to tracked files. This cannot be undone.")
		}
	}

	static var allConfirmation: ConfirmationDialogState<Action.ConfirmAction> {
		ConfirmationDialogState {
			TextState("Discard all local changes?")
		} actions: {
			ButtonState(role: .destructive, action: .confirmAll) {
				TextState("Discard All Changes")
			}
			ButtonState(role: .cancel) {
				TextState("Cancel")
			}
		} message: {
			TextState("This reverts tracked changes and permanently deletes untracked files. This cannot be undone.")
		}
	}
}
