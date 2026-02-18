import ComposableArchitecture
import Foundation

@Reducer
struct FileDiffViewer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var fileDiff: FileDiff?
		var fileId: String?
		var fileIsStaged: Bool?

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}
	}

	enum Action: Sendable {
		case load(FileChange, isStaged: Bool)
		case loadResponse(FileDiff?)
		case stageHunk(DiffHunk)
		case unstageHunk(DiffHunk)
		case discardHunk(DiffHunk)
		case delegate(Delegate)

		enum Delegate: Sendable {
			case fileHasNoChanges(fileId: String, isStaged: Bool)
			case stageHunk(FileChange, DiffHunk)
			case unstageHunk(FileChange, DiffHunk)
			case discardHunk(FileChange, DiffHunk)
		}
	}

	private nonisolated enum CancellableId: Hashable, Sendable {
		case loadDiff
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	var body: some Reducer<State, Action> {
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
						state.fileDiff = nil
						return .none
					}

					state.fileId = nil
					state.fileIsStaged = nil
					state.fileDiff = nil
					return .send(.delegate(.fileHasNoChanges(fileId: fileId, isStaged: isStaged)))
				}

				state.fileDiff = diff
				return .none

			case let .stageHunk(hunk):
				guard let file = state.fileDiff?.fileChange else {
					return .none
				}

				return .send(.delegate(.stageHunk(file, hunk)))

			case let .unstageHunk(hunk):
				guard let file = state.fileDiff?.fileChange else {
					return .none
				}

				return .send(.delegate(.unstageHunk(file, hunk)))

			case let .discardHunk(hunk):
				guard let file = state.fileDiff?.fileChange else {
					return .none
				}

				return .send(.delegate(.discardHunk(file, hunk)))

			case .delegate:
				return .none
			}
		}
	}
}
