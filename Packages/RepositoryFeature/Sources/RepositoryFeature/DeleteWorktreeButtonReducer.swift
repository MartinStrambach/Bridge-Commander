import ComposableArchitecture
import Foundation
import AppUI
import Settings
import ToolsIntegration
import GitCore

@Reducer
struct DeleteWorktreeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let name: String
		let path: String
		let defaultBranch: String
		var isRemoving: Bool = false
		@Shared(.deleteDerivedDataOnWorktreeDelete)
		var deleteDerivedDataOnWorktreeDelete = true
		@Presents
		var confirmationSheet: DeleteWorktreeConfirmationReducer.State?
		@Presents
		var errorAlert: AlertState<Action.ErrorAlert>?
		@Presents
		var removalWarningAlert: AlertState<Action.RemovalWarningAlert>?

		/// Whether the worktree's row has to stay although a scan no longer finds the worktree.
		/// Git drops it from its list before the delete has cleared the branch and DerivedData,
		/// and the watcher rescans within the second: a row taken then leaves the delete's result
		/// with nowhere to go, and takes the warning alert, which hangs off the row, with it. Not
		/// for an error: git refused, so the worktree is still there and still scanned.
		var holdsRowAfterRemoval: Bool {
			isRemoving || removalWarningAlert != nil
		}
	}

	enum Action {
		case showConfirmation
		case derivedDataChecked(found: Bool)
		case confirmationSheet(PresentationAction<DeleteWorktreeConfirmationReducer.Action>)
		case errorAlert(PresentationAction<ErrorAlert>)
		case removalWarningAlert(PresentationAction<RemovalWarningAlert>)
		case didRemoveSuccessfully
		case didRemoveSuccessfullyWithWarning(String)
		case didFailWithError(String)

		enum ErrorAlert: Equatable {}
		enum RemovalWarningAlert: Equatable {}
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .showConfirmation:
				state.confirmationSheet = DeleteWorktreeConfirmationReducer.State(name: state.name)
				guard state.deleteDerivedDataOnWorktreeDelete else {
					return .none
				}
				return .run { [path = state.path] send in
					await send(.derivedDataChecked(found: XcodeDerivedDataHelper.hasDerivedData(forWorktreePath: path)))
				}

			case let .derivedDataChecked(found):
				state.confirmationSheet?.deletesDerivedData = found
				return .none

			case let .confirmationSheet(.presented(.confirmTapped(forceRemoval: force, deleteLocalBranch: deleteLocalBranch))):
				state.confirmationSheet = nil
				state.isRemoving = true
				return .run { [
					name = state.name,
					path = state.path,
					defaultBranch = state.defaultBranch,
					deleteDerivedData = state.deleteDerivedDataOnWorktreeDelete
				] send in
					// The branch and the main repository path must be resolved while
					// the worktree still exists; its directory is gone once removal
					// succeeds. Resolution also applies the guardrails: detached HEAD
					// and the default branch resolve to nil and are never deleted.
					let branchToDelete = deleteLocalBranch
						? await GitLocalBranchDeleter.resolveDeletableBranch(
							worktreePath: path,
							defaultBranch: defaultBranch
						)
						: nil
					let outcome: GitWorktreeRemover.Outcome
					do {
						outcome = try await GitWorktreeRemover.removeWorktree(name: name, path: path, force: force)
					}
					catch {
						await send(.didFailWithError(error.localizedDescription))
						return
					}
					var warnings: [String] = []
					// Git reports this as a failure, yet the worktree is gone from the repository:
					// the rest of the cleanup still applies, and the folder is the user's to clear.
					if case let .removedLeavingFiles(message) = outcome {
						warnings.append("Git could not delete every file. What is left is still in \(path):\n\(message)")
					}
					if let branchToDelete {
						do {
							try await GitLocalBranchDeleter.deleteBranch(branchToDelete)
						}
						catch {
							warnings.append(error.localizedDescription)
						}
					}
					if deleteDerivedData {
						do {
							try XcodeDerivedDataHelper.deleteDerivedData(forWorktreePath: path)
						}
						catch {
							warnings.append("DerivedData cleanup failed: \(error.localizedDescription)")
						}
					}
					if warnings.isEmpty {
						await send(.didRemoveSuccessfully)
					}
					else {
						await send(.didRemoveSuccessfullyWithWarning(warnings.joined(separator: "\n\n")))
					}
				}

			case .confirmationSheet(.presented(.cancelTapped)):
				state.confirmationSheet = nil
				return .none

			case .confirmationSheet:
				return .none

			case .didRemoveSuccessfully:
				state.isRemoving = false
				return .none

			case let .didRemoveSuccessfullyWithWarning(message):
				state.isRemoving = false
				state.removalWarningAlert = AlertState {
					TextState("Worktree Removed")
				} actions: {
					ButtonState(role: .cancel) { TextState("OK") }
				} message: {
					TextState("Worktree was removed successfully, but:\n\n\(message)")
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

			case .removalWarningAlert:
				return .none
			}
		}
		.ifLet(\.$confirmationSheet, action: \.confirmationSheet) {
			DeleteWorktreeConfirmationReducer()
		}
		.ifLet(\.$errorAlert, action: \.errorAlert)
		.ifLet(\.$removalWarningAlert, action: \.removalWarningAlert)
	}
}
