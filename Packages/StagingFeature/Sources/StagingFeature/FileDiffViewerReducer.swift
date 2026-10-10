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
		/// The selected file and side: set as soon as a load starts, so they can run ahead of the
		/// diff on screen until its response arrives.
		var fileId: String?
		var fileIsStaged: Bool?
		/// The side of the diff on screen, set together with it. The view picks Stage or Unstage
		/// buttons from this, never from `fileIsStaged`, which may already name the other side.
		var diffIsStaged = false

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}

		func hunk(id: String) -> GitCore.DiffHunk? {
			fileDiff?.hunks.first { $0.id == id }
		}

		/// Drops the current file. Every caller must clear all of these together, so the display
		/// diff cannot outlive the selection it belongs to. Outside this reducer, send `.clear`,
		/// which also cancels a load still in flight.
		mutating func clearSelection() {
			fileId = nil
			fileIsStaged = nil
			fileDiff = nil
			displayDiff = nil
			diffIsStaged = false
		}
	}

	public enum Action {
		case load(FileChange, isStaged: Bool)
		case loadResponse(fileId: String, isStaged: Bool, GitCore.FileDiff?)
		case clear
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
					await send(.loadResponse(fileId: file.id, isStaged: isStaged, diff))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case let .loadResponse(fileId, isStaged, diff):
				// An answer to an earlier selection must not land on the current one.
				guard fileId == state.fileId, isStaged == state.fileIsStaged else {
					return .none
				}

				guard let diff else {
					state.clearSelection()
					return .send(.delegate(.fileHasNoChanges(fileId: fileId, isStaged: isStaged)))
				}

				state.fileDiff = diff
				state.displayDiff = diff.toAppUI()
				state.diffIsStaged = isStaged
				return .none

			case .clear:
				state.clearSelection()
				return .cancel(id: CancellableId.loadDiff)

			case let .stageHunk(hunkId):
				guard let file = state.fileDiff?.fileChange, let hunk = state.hunk(id: hunkId) else {
					return .none
				}

				return .send(.delegate(.stageHunk(file, hunk)))

			case let .unstageHunk(hunkId):
				guard let file = state.fileDiff?.fileChange, let hunk = state.hunk(id: hunkId) else {
					return .none
				}

				return .send(.delegate(.unstageHunk(file, hunk)))

			case let .discardHunk(hunkId):
				guard let file = state.fileDiff?.fileChange, let hunk = state.hunk(id: hunkId) else {
					return .none
				}

				return .send(.delegate(.discardHunk(file, hunk)))

			case .delegate:
				return .none
			}
		}
	}
}
