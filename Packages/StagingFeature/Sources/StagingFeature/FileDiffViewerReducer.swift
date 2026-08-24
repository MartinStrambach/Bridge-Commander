import AppUI
import ComposableArchitecture
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

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}

		func hunk(id: String) -> GitCore.DiffHunk? {
			fileDiff?.hunks.first { $0.id == id }
		}

		/// Drops the current file. Every caller must clear all four properties together, so the
		/// display diff cannot outlive the selection it belongs to.
		mutating func clearSelection() {
			fileId = nil
			fileIsStaged = nil
			fileDiff = nil
			displayDiff = nil
		}
	}

	public enum Action {
		case load(FileChange, isStaged: Bool)
		case loadResponse(GitCore.FileDiff?)
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
					await send(.loadResponse(diff))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case let .loadResponse(diff):
				guard let diff else {
					guard let fileId = state.fileId, let isStaged = state.fileIsStaged else {
						state.clearSelection()
						return .none
					}

					state.clearSelection()
					return .send(.delegate(.fileHasNoChanges(fileId: fileId, isStaged: isStaged)))
				}

				state.fileDiff = diff
				state.displayDiff = diff.toAppUI()
				return .none

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
