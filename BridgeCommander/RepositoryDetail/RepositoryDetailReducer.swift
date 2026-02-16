import ComposableArchitecture
import Foundation

@Reducer
struct RepositoryDetail {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var selectedFileDiff: FileDiff?
		var stagedChanges: [FileChange] = []
		var unstagedChanges: [FileChange] = []

		var selectedFileId: String?
		var selectedFileIsStaged: Bool?
		var selectedStagedFileIds: Set<String> = []
		var selectedUnstagedFileIds: Set<String> = []
		var lastActionedFileId: String?
		var lastActionedFileIndex: Int?
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
		case deleteUntrackedFiles([FileChange])
		case discardFileChanges([FileChange])
		case discardHunk(FileChange, DiffHunk)
		case loadChanges
		case loadChangesResponse(GitFileChanges)
		case openFileInIDE(FileChange)
		case openTerminalButtonTapped
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

	@Shared(.terminalOpeningBehavior)
	private var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .loadChanges:
				return .run { [path = state.repositoryPath] send in
					// Retry logic to handle git index race conditions
					var changes = await gitStagingClient.fetchFileChanges(path)

					// If we get empty results, retry once after a delay
					if changes.staged.isEmpty, changes.unstaged.isEmpty {
						try await Task.sleep(nanoseconds: 200_000_000) // 200ms
						changes = await gitStagingClient.fetchFileChanges(path)
					}

					await send(.loadChangesResponse(changes))
				}
				.cancellable(id: CancellableId.loadChanges, cancelInFlight: true)

			case let .loadChangesResponse(changes):
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
				// Track the index of the last actioned file in the unstaged list
				if let lastFileId = files.last?.id {
					state.lastActionedFileIndex = state.unstagedChanges.firstIndex(where: { $0.id == lastFileId })
				}

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
				// Track the index of the last actioned file in the staged list
				if let lastFileId = files.last?.id {
					state.lastActionedFileIndex = state.stagedChanges.firstIndex(where: { $0.id == lastFileId })
				}

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

			case let .discardFileChanges(files):
				guard !files.isEmpty else {
					return .none
				}

				let filePaths = files.map(\.path)
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.discardFileChanges(path, filePaths)
					}
					await send(.operationCompleted(result))
				}

			case let .deleteUntrackedFiles(files):
				guard !files.isEmpty else {
					return .none
				}

				let filePaths = files.map(\.path)
				return .run { [path = state.repositoryPath] send in
					let result = await Result {
						try await gitStagingClient.deleteUntrackedFiles(path, filePaths)
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

			case .openTerminalButtonTapped:
				return .run { [path = state.repositoryPath, behavior = terminalOpeningBehavior] _ in
					await TerminalLauncher.openTerminal(at: path, behavior: behavior)
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
		guard state.lastActionedFileId != nil else {
			// No previous action - check if we need initial selection
			if let selectedFileId = state.selectedFileId, let wasStaged = state.selectedFileIsStaged {
				// Refresh diff if file still exists
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
			else {
				// Initial load - select first unstaged file, or first staged file if no unstaged files
				if let firstUnstaged = changes.unstaged.first {
					return .send(.selectFile(firstUnstaged, isStaged: false))
				}
				else if let firstStaged = changes.staged.first {
					return .send(.selectFile(firstStaged, isStaged: true))
				}
			}
			return .none
		}

		// Clear tracking state
		state.lastActionedFileId = nil
		let actionedIndex = state.lastActionedFileIndex
		state.lastActionedFileIndex = nil
		state.selectedUnstagedFileIds.removeAll()
		state.selectedStagedFileIds.removeAll()

		// Determine which list to select from (the source list, where the file came from)
		let (sourceList, targetList, isStaged) = state.wasStaging
			? (changes.unstaged, changes.staged, false)
			: (changes.staged, changes.unstaged, true)

		// Try to select file at the same index in the source list
		if let index = actionedIndex {
			// Try same index
			if index < sourceList.count {
				return .send(.selectFile(sourceList[index], isStaged: isStaged))
			}
			// Try previous file if we're at the end
			else if index > 0, !sourceList.isEmpty {
				return .send(.selectFile(sourceList[sourceList.count - 1], isStaged: isStaged))
			}
		}

		// No files in source list, try first file in target list
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
