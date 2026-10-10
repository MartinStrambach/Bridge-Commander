import AppUI
import ComposableArchitecture
import DiffModelMapping
import Foundation
import GitCore

@Reducer
public struct FileDiffViewer: Sendable {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		/// The git model, kept so hunk actions can be resolved back to a patchable hunk.
		var fileDiff: GitCore.FileDiff?
		/// The same diff in AppUI's models, converted once here rather than on every render.
		var displayDiff: AppUI.FileDiff?
		var fileId: String?
		var fileIsStaged: Bool?
		/// Set from a hunk's Stage/Unstage/Discard until the diff reloads, and further hunk actions
		/// are dropped meanwhile: the hunks on screen are stale until then, and a double click used
		/// to apply the same patch twice (an added hunk was staged twice).
		var isApplyingHunk = false

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}

		func hunk(id: String) -> GitCore.DiffHunk? {
			fileDiff?.hunks.first { $0.id == id }
		}

		/// Drops the current file. Every caller must clear these properties together, so the
		/// display diff cannot outlive the selection it belongs to.
		mutating func clearSelection() {
			fileId = nil
			fileIsStaged = nil
			fileDiff = nil
			displayDiff = nil
			isApplyingHunk = false
		}
	}

	public enum Action {
		case load(FileChange, isStaged: Bool)
		case loadResponse(fileId: String, isStaged: Bool, diff: GitCore.FileDiff?, displayDiff: AppUI.FileDiff?)
		case stageHunk(hunkId: String)
		case unstageHunk(hunkId: String)
		case discardHunk(hunkId: String)
		case delegate(Delegate)

		@CasePathable
		public enum Delegate {
			case fileHasNoChanges(fileId: String, isStaged: Bool)
			case stageHunk(FileChange, GitCore.DiffHunk)
			case unstageHunk(FileChange, GitCore.DiffHunk)
			case discardHunk(FileChange, GitCore.DiffHunk)
		}
	}

	private nonisolated enum CancellableId: Hashable {
		case loadDiff
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case let .load(file, isStaged):
				state.fileId = file.id
				state.fileIsStaged = isStaged
				return .run { [path = state.repositoryPath] send in
					let diff = await gitStagingClient.fetchFileDiff(path, file, isStaged)
					// Mapped here rather than in the reducer, which runs on the main actor: a large
					// diff's conversion is long enough to hang the window.
					await send(.loadResponse(fileId: file.id, isStaged: isStaged, diff: diff, displayDiff: diff?.toAppUI()))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case let .loadResponse(fileId, isStaged, diff, displayDiff):
				// Clearing the selection does not cancel the load, so its diff may arrive for a file
				// that is no longer selected; showing it would also bring back its hunk buttons.
				guard fileId == state.fileId, isStaged == state.fileIsStaged else {
					return .none
				}

				state.isApplyingHunk = false
				guard let diff, let displayDiff else {
					state.clearSelection()
					return .send(.delegate(.fileHasNoChanges(fileId: fileId, isStaged: isStaged)))
				}

				state.fileDiff = diff
				state.displayDiff = displayDiff
				return .none

			case let .stageHunk(hunkId):
				return applyHunk(id: hunkId, state: &state, Action.Delegate.stageHunk)

			case let .unstageHunk(hunkId):
				return applyHunk(id: hunkId, state: &state, Action.Delegate.unstageHunk)

			case let .discardHunk(hunkId):
				return applyHunk(id: hunkId, state: &state, Action.Delegate.discardHunk)

			case .delegate:
				return .none
			}
		}
	}

	private func applyHunk(
		id hunkId: String,
		state: inout State,
		_ delegate: (FileChange, GitCore.DiffHunk) -> Action.Delegate
	) -> EffectOf<FileDiffViewer> {
		guard
			!state.isApplyingHunk,
			let file = state.fileDiff?.fileChange,
			let hunk = state.hunk(id: hunkId)
		else {
			return .none
		}

		state.isApplyingHunk = true
		return .send(.delegate(delegate(file, hunk)))
	}
}
