import AppUI
import ComposableArchitecture
import DiffModelMapping
import Foundation
import GitCore

/// What one commit changed: its file list and the diff of the selected file.
///
/// Read-only throughout. Selecting a commit or a file only reads objects out of the repository —
/// it never checks anything out, so HEAD, the index and the working tree are left alone.
@Reducer
public struct CommitDetailReducer: Sendable {
	@ObservableState
	public struct State: Equatable, Identifiable {
		let repositoryPath: String
		let commit: GitLogCommit

		var files: [GitCore.FileChange] = []
		var isLoadingFiles = false

		var selectedFileId: GitCore.FileChange.ID?
		/// The selected file's diff in AppUI's models, converted once here rather than per render.
		var displayDiff: AppUI.FileDiff?
		var isLoadingDiff = false

		public var id: String { commit.hash }

		/// True once the file list has loaded and turned out to be empty — a commit that changed
		/// nothing against its first parent (an empty commit, or a merge that took no changes).
		var hasNoChanges: Bool {
			!isLoadingFiles && files.isEmpty
		}

		init(repositoryPath: String, commit: GitLogCommit) {
			self.repositoryPath = repositoryPath
			self.commit = commit
		}
	}

	public enum Action: Equatable {
		case task
		case filesLoaded([GitCore.FileChange])
		case fileSelected(GitCore.FileChange.ID?)
		case diffLoaded(AppUI.FileDiff?)
	}

	private nonisolated enum CancellableId: Hashable {
		case loadFiles
		case loadDiff
	}

	@Dependency(GitCommitDiffClient.self)
	private var gitCommitDiffClient

	public init() {}

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .task:
				state.isLoadingFiles = true
				return .run { [path = state.repositoryPath, hash = state.commit.hash] send in
					await send(.filesLoaded(gitCommitDiffClient.fetchFileChanges(path, hash)))
				}
				.cancellable(id: CancellableId.loadFiles, cancelInFlight: true)

			case let .filesLoaded(files):
				state.isLoadingFiles = false
				state.files = files

				// Open the first file straight away so the diff is visible without a second click.
				return .send(.fileSelected(files.first?.id))

			case let .fileSelected(fileId):
				state.selectedFileId = fileId
				state.displayDiff = nil

				guard
					let fileId,
					let file = state.files.first(where: { $0.id == fileId })
				else {
					state.isLoadingDiff = false
					return .cancel(id: CancellableId.loadDiff)
				}

				state.isLoadingDiff = true
				return .run { [path = state.repositoryPath, hash = state.commit.hash] send in
					let diff = await gitCommitDiffClient.fetchFileDiff(path, hash, file)
					await send(.diffLoaded(diff?.toAppUI()))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case let .diffLoaded(diff):
				state.isLoadingDiff = false
				state.displayDiff = diff
				return .none
			}
		}
	}
}
