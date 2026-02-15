import ComposableArchitecture
import Foundation

@Reducer
struct RepositoryDetail {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isLoading = false
		var selectedFileDiff: FileDiff?
		var stagedChanges: [FileChange] = []
		var unstagedChanges: [FileChange] = []

		var selectedFileId: String?
		var selectedFileIsStaged: Bool?
		var selectedStagedFileIds: Set<String> = []
		var selectedUnstagedFileIds: Set<String> = []
		var lastActionedFileId: String?
		var wasStaging = false

		var hasChanges: Bool {
			!stagedChanges.isEmpty || !unstagedChanges.isEmpty
		}

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}
	}

	enum Action: Sendable {
		case cancelButtonTapped
		case deleteUntrackedFile(FileChange)
		case discardFileChanges(FileChange)
		case discardHunk(FileChange, DiffHunk)
		case loadChanges
		case loadChangesResponse(GitFileChanges)
		case openFileInIDE(FileChange)
		case selectFile(FileChange, isStaged: Bool)
		case selectFileDiffResponse(FileDiff?)
		case spaceKeyPressed
		case stageFiles([FileChange])
		case unstageFiles([FileChange])
		case stageHunk(FileChange, DiffHunk)
		case unstageHunk(FileChange, DiffHunk)
		case updateSelection(Set<String>, isStaged: Bool)
		case operationCompleted(Result<Void, Error>)
	}

	private nonisolated enum CancellableId: Hashable, Sendable {
		case loadChanges
		case loadDiff
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	@Dependency(\.dismiss)
	private var dismiss

	@Shared(.androidStudioPath)
	private var androidStudioPath = "/Applications/Android Studio.app/Contents/MacOS/studio"

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .loadChanges:
				state.isLoading = true
				return .run { [path = state.repositoryPath] send in
					let changes = await gitStagingClient.fetchFileChanges(path)
					await send(.loadChangesResponse(changes))
				}
				.cancellable(id: CancellableId.loadChanges, cancelInFlight: true)

			case let .loadChangesResponse(changes):
				state.isLoading = false
				state.stagedChanges = changes.staged
				state.unstagedChanges = changes.unstaged

				return handleAutoSelection(state: &state, changes: changes)

			case let .selectFile(file, isStaged):
				state.selectedFileId = file.id
				state.selectedFileIsStaged = isStaged

				// Update multi-selection to match single selection
				if isStaged {
					state.selectedStagedFileIds = [file.id]
					state.selectedUnstagedFileIds = []
				}
				else {
					state.selectedUnstagedFileIds = [file.id]
					state.selectedStagedFileIds = []
				}

				return .run { [path = state.repositoryPath] send in
					let diff = await gitStagingClient.fetchFileDiff(path, file, isStaged)
					await send(.selectFileDiffResponse(diff))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case let .selectFileDiffResponse(diff):
				state.selectedFileDiff = diff
				return .none

			case let .stageFiles(files):
				guard !files.isEmpty else {
					return .none
				}

				state.lastActionedFileId = files.last?.id
				state.wasStaging = true

				let filePaths = files.map(\.path)
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.stageFiles(path, filePaths)
					}
					await send(.operationCompleted(result))
				}

			case let .unstageFiles(files):
				guard !files.isEmpty else {
					return .none
				}

				state.lastActionedFileId = files.last?.id
				state.wasStaging = false

				let filePaths = files.map(\.path)
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.unstageFiles(path, filePaths)
					}
					await send(.operationCompleted(result))
				}

			case let .stageHunk(file, hunk):
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.stageHunk(path, file, hunk)
					}
					await send(.operationCompleted(result))
				}

			case let .unstageHunk(file, hunk):
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.unstageHunk(path, file, hunk)
					}
					await send(.operationCompleted(result))
				}

			case let .discardHunk(file, hunk):
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.discardHunk(path, file, hunk)
					}
					await send(.operationCompleted(result))
				}

			case let .discardFileChanges(file):
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.discardFileChanges(path, file.path)
					}
					await send(.operationCompleted(result))
				}

			case let .deleteUntrackedFile(file):
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.deleteUntrackedFile(path, file.path)
					}
					await send(.operationCompleted(result))
				}

			case .operationCompleted(.success):
				return .send(.loadChanges)

			case let .operationCompleted(.failure(error)):
				print("Operation failed: \(error)")
				return .none

			case let .openFileInIDE(file):
				return .run { [path = state.repositoryPath, studioPath = androidStudioPath] _ in
					do {
						try await FileOpener.openFileInIDE(
							filePath: file.path,
							repositoryPath: path,
							androidStudioPath: studioPath
						)
					}
					catch {
						print("Failed to open file in IDE: \(error)")
					}
				}

			case .cancelButtonTapped:
				return .run { _ in
					await dismiss()
				}

			case let .updateSelection(selectedIds, isStaged):
				if isStaged {
					state.selectedStagedFileIds = selectedIds
					state.selectedUnstagedFileIds = []
				}
				else {
					state.selectedUnstagedFileIds = selectedIds
					state.selectedStagedFileIds = []
				}

				// Update diff view to show first selected file
				guard
					let firstId = selectedIds.first,
					let file = (isStaged ? state.stagedChanges : state.unstagedChanges)
						.first(where: { $0.id == firstId })
				else {
					state.selectedFileId = nil
					state.selectedFileIsStaged = nil
					state.selectedFileDiff = nil
					return .none
				}

				state.selectedFileId = file.id
				state.selectedFileIsStaged = isStaged

				return .run { [path = state.repositoryPath] send in
					let diff = await gitStagingClient.fetchFileDiff(path, file, isStaged)
					await send(.selectFileDiffResponse(diff))
				}
				.cancellable(id: CancellableId.loadDiff, cancelInFlight: true)

			case .spaceKeyPressed:
				if !state.selectedUnstagedFileIds.isEmpty {
					let filesToStage = state.unstagedChanges.filter { state.selectedUnstagedFileIds.contains($0.id) }
					state.selectedUnstagedFileIds.removeAll()
					return .send(.stageFiles(filesToStage))
				}
				else if !state.selectedStagedFileIds.isEmpty {
					let filesToUnstage = state.stagedChanges.filter { state.selectedStagedFileIds.contains($0.id) }
					state.selectedStagedFileIds.removeAll()
					return .send(.unstageFiles(filesToUnstage))
				}
				return .none
			}
		}
	}

	// MARK: - Helpers

	private func handleAutoSelection(
		state: inout State,
		changes: GitFileChanges
	) -> Effect<Action> {
		guard let lastFileId = state.lastActionedFileId else {
			// No auto-selection needed, but refresh diff if file still exists
			if let selectedFileId = state.selectedFileId, let wasStaged = state.selectedFileIsStaged {
				if wasStaged, let file = changes.staged.first(where: { $0.id == selectedFileId }) {
					return .send(.selectFile(file, isStaged: true))
				}
				else if !wasStaged, let file = changes.unstaged.first(where: { $0.id == selectedFileId }) {
					return .send(.selectFile(file, isStaged: false))
				}
				else {
					state.selectedFileId = nil
					state.selectedFileIsStaged = nil
					state.selectedFileDiff = nil
				}
			}
			return .none
		}

		state.lastActionedFileId = nil
		state.selectedUnstagedFileIds.removeAll()
		state.selectedStagedFileIds.removeAll()

		let (sourceList, targetList, isStaged) = state.wasStaging
			? (changes.unstaged, changes.staged, false)
			: (changes.staged, changes.unstaged, true)

		// Try to select next file at same position in source list
		if let oldIndex = sourceList.firstIndex(where: { $0.id == lastFileId }) {
			if oldIndex < sourceList.count {
				return .send(.selectFile(sourceList[oldIndex], isStaged: isStaged))
			}
			else if oldIndex > 0, !sourceList.isEmpty {
				return .send(.selectFile(sourceList[oldIndex - 1], isStaged: isStaged))
			}
		}

		// No files in source, try target list
		if let firstTarget = targetList.first {
			return .send(.selectFile(firstTarget, isStaged: !isStaged))
		}

		// No files at all, clear selection
		state.selectedFileId = nil
		state.selectedFileIsStaged = nil
		state.selectedFileDiff = nil
		return .none
	}
}
