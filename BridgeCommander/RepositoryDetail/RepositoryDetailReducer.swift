import ComposableArchitecture
import Foundation

@Reducer
struct RepositoryDetail {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var diffViewer: FileDiffViewer.State
		var mergeStatus: MergeStatus.State
		var staged: FileChangeList.State
		var unstaged: FileChangeList.State
		@Presents
		var alert: GitAlertReducer.State?
		@Presents
		var commitSheet: CommitReducer.State?

		var lastActionedFileId: String?
		var lastActionedFileIndex: Int?
		var wasStaging = false

		var hasChanges: Bool {
			!staged.files.isEmpty || !unstaged.files.isEmpty
		}

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
			self.diffViewer = FileDiffViewer.State(repositoryPath: repositoryPath)
			self.mergeStatus = MergeStatus.State(repositoryPath: repositoryPath)
			self.staged = FileChangeList.State(repositoryPath: repositoryPath, listType: .staged)
			self.unstaged = FileChangeList.State(repositoryPath: repositoryPath, listType: .unstaged)
		}
	}

	enum Action: Sendable {
		case alert(PresentationAction<GitAlertReducer.Action>)
		case cancelButtonTapped
		case commitButtonTapped
		case commitSheet(PresentationAction<CommitReducer.Action>)
		case deleteFilesCompleted([FileChange])
		case discardFilesCompleted([FileChange])
		case diffViewer(FileDiffViewer.Action)
		case loadChanges
		case loadChangesResponse(GitFileChanges)
		case mergeStatus(MergeStatus.Action)
		case openTerminalButtonTapped
		case selectFile(FileChange, isStaged: Bool)
		case staged(FileChangeList.Action)
		case stageFilesCompleted([FileChange])
		case unstaged(FileChangeList.Action)
		case unstageFilesCompleted([FileChange])
		case operationCompleted(Result<Void, Error>)
	}

	private nonisolated enum CancellableId: Hashable, Sendable {
		case loadChanges
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	@Dependency(\.dismiss)
	private var dismiss

	@Shared(.terminalOpeningBehavior)
	private var terminalOpeningBehavior = TerminalOpeningBehavior.newTab

	var body: some Reducer<State, Action> {
		Scope(state: \.staged, action: \.staged) { FileChangeList() }
		Scope(state: \.unstaged, action: \.unstaged) { FileChangeList() }
		Scope(state: \.diffViewer, action: \.diffViewer) { FileDiffViewer() }
		Scope(state: \.mergeStatus, action: \.mergeStatus) { MergeStatus() }

		Reduce { state, action in
			switch action {
			case .loadChanges,
			     .operationCompleted(.success):
				return .merge(
					.run { [path = state.repositoryPath] send in
						// Retry logic to handle git index race conditions
						var changes = await gitStagingClient.fetchFileChanges(path)
						if changes.staged.isEmpty, changes.unstaged.isEmpty {
							try await Task.sleep(nanoseconds: 200_000_000) // 200ms
							changes = await gitStagingClient.fetchFileChanges(path)
						}
						await send(.loadChangesResponse(changes))
					},
					.run { [path = state.repositoryPath] send in
						let isMergeInProgress = GitMergeDetector.isGitOperationInProgress(at: path)
						await send(.mergeStatus(.loadStatusResponse(isMergeInProgress)))
					}
				)
				.cancellable(id: CancellableId.loadChanges, cancelInFlight: true)

			case let .loadChangesResponse(changes):
				state.staged.isLoading = false
				state.staged.files = changes.staged
				state.unstaged.isLoading = false
				state.unstaged.files = changes.unstaged
				return handleAutoSelection(state: &state, staged: changes.staged, unstaged: changes.unstaged)

			case let .selectFile(file, isStaged):
				if isStaged {
					state.staged.selectedFileIds = [file.id]
					state.unstaged.selectedFileIds = []
				}
				else {
					state.unstaged.selectedFileIds = [file.id]
					state.staged.selectedFileIds = []
				}
				return .send(.diffViewer(.load(file, isStaged: isStaged)))

			case let .unstaged(.delegate(.toggleAll(files))):
				guard !files.isEmpty else {
					return .none
				}

				trackLastActioned(files, wasStaging: true, sourceList: state.unstaged.files, state: &state)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.stageFiles(path, paths)
						await send(.stageFilesCompleted(files))
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case let .stageFilesCompleted(files):
				moveFiles(
					files,
					from: \.unstaged.files,
					to: \.staged.files,
					statusTransform: { $0 == .untracked ? .added : $0 },
					state: &state
				)
				return handleAutoSelection(state: &state, staged: state.staged.files, unstaged: state.unstaged.files)

			case let .staged(.delegate(.toggleAll(files))):
				guard !files.isEmpty else {
					return .none
				}

				trackLastActioned(files, wasStaging: false, sourceList: state.staged.files, state: &state)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.unstageFiles(path, paths)
						await send(.unstageFilesCompleted(files))
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case let .unstageFilesCompleted(files):
				moveFiles(
					files,
					from: \.staged.files,
					to: \.unstaged.files,
					statusTransform: { $0 == .added ? .untracked : $0 },
					state: &state
				)
				return handleAutoSelection(state: &state, staged: state.staged.files, unstaged: state.unstaged.files)

			case let .unstaged(.delegate(.discardChanges(files))):
				guard !files.isEmpty else {
					return .none
				}

				trackLastActioned(files, wasStaging: true, sourceList: state.unstaged.files, state: &state)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.discardFileChanges(path, paths)
						await send(.discardFilesCompleted(files))
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case let .deleteFilesCompleted(files),
			     let .discardFilesCompleted(files):
				return removeFromUnstaged(files, state: &state)

			case let .unstaged(.delegate(.deleteUntracked(files))):
				guard !files.isEmpty else {
					return .none
				}

				trackLastActioned(files, wasStaging: true, sourceList: state.unstaged.files, state: &state)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.deleteUntrackedFiles(path, paths)
						await send(.deleteFilesCompleted(files))
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case let .unstaged(.delegate(.deleteConflicted(files))):
				guard !files.isEmpty else {
					return .none
				}

				trackLastActioned(files, wasStaging: true, sourceList: state.unstaged.files, state: &state)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.deleteConflictedFiles(path, paths)
						await send(.deleteFilesCompleted(files))
					}
					catch {
						await send(.operationCompleted(.failure(error)))
					}
				}

			case let .diffViewer(.delegate(.fileHasNoChanges(fileId, isStaged))):
				let list = isStaged ? state.staged.files : state.unstaged.files
				state.lastActionedFileId = fileId
				state.lastActionedFileIndex = list.firstIndex { $0.id == fileId }
				state.wasStaging = !isStaged
				if isStaged {
					state.staged.files.removeAll { $0.id == fileId }
				}
				else {
					state.unstaged.files.removeAll { $0.id == fileId }
				}
				return handleAutoSelection(state: &state, staged: state.staged.files, unstaged: state.unstaged.files)

			case let .diffViewer(.delegate(.stageHunk(file, hunk))):
				return .run { [path = state.repositoryPath] send in
					await send(.operationCompleted(Result { try await gitStagingClient.stageHunk(path, file, hunk) }))
				}

			case let .diffViewer(.delegate(.unstageHunk(file, hunk))):
				return .run { [path = state.repositoryPath] send in
					await send(.operationCompleted(Result { try await gitStagingClient.unstageHunk(path, file, hunk) }))
				}

			case let .diffViewer(.delegate(.discardHunk(file, hunk))):
				return .run { [path = state.repositoryPath] send in
					await send(.operationCompleted(Result { try await gitStagingClient.discardHunk(path, file, hunk) }))
				}

			// selection — child already updated its own selectedFileIds via Scope;
			// parent clears the other list and triggers diff load
			case let .staged(.updateSelection(ids)):
				state.unstaged.selectedFileIds = []
				guard
					let firstId = ids.first,
					let file = state.staged.files.first(where: { $0.id == firstId })
				else {
					state.diffViewer.fileId = nil
					state.diffViewer.fileIsStaged = nil
					state.diffViewer.fileDiff = nil
					return .none
				}

				return .send(.diffViewer(.load(file, isStaged: true)))

			case let .unstaged(.updateSelection(ids)):
				state.staged.selectedFileIds = []
				guard
					let firstId = ids.first,
					let file = state.unstaged.files.first(where: { $0.id == firstId })
				else {
					state.diffViewer.fileId = nil
					state.diffViewer.fileIsStaged = nil
					state.diffViewer.fileDiff = nil
					return .none
				}

				return .send(.diffViewer(.load(file, isStaged: false)))

			case let .mergeStatus(.delegate(.operationCompleted(result))):
				return .send(.operationCompleted(result))

			case let .operationCompleted(.failure(error)):
				state.alert = GitAlertReducer.State(
					title: "Finish Merge Failed",
					message: error.localizedDescription,
					isError: true
				)
				return .none

			case .commitButtonTapped:
				state.commitSheet = CommitReducer.State(repositoryPath: state.repositoryPath)
				return .none

			case .commitSheet(.presented(.delegate(.commitSucceeded))):
				return .send(.operationCompleted(.success(())))

			case .cancelButtonTapped:
				return .run { _ in await dismiss() }

			case .openTerminalButtonTapped:
				return .run { [path = state.repositoryPath, behavior = terminalOpeningBehavior] _ in
					await TerminalLauncher.openTerminal(at: path, behavior: behavior)
				}

			default:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			GitAlertReducer()
		}
		.ifLet(\.$commitSheet, action: \.commitSheet) {
			CommitReducer()
		}
	}

	// MARK: - Helpers

	private func trackLastActioned(
		_ files: [FileChange],
		wasStaging: Bool,
		sourceList: [FileChange],
		state: inout State
	) {
		state.wasStaging = wasStaging
		if let lastId = files.last?.id {
			state.lastActionedFileId = lastId
			state.lastActionedFileIndex = sourceList.firstIndex { $0.id == lastId }
		}
	}

	private func moveFiles(
		_ files: [FileChange],
		from source: WritableKeyPath<State, [FileChange]>,
		to target: WritableKeyPath<State, [FileChange]>,
		statusTransform: (FileChangeStatus) -> FileChangeStatus,
		state: inout State
	) {
		let fileIds = Set(files.map(\.id))
		state[keyPath: source].removeAll { fileIds.contains($0.id) }
		let existingIds = Set(state[keyPath: target].map(\.id))
		let newFiles = files
			.filter { !existingIds.contains($0.id) }
			.map { FileChange(path: $0.path, status: statusTransform($0.status), oldPath: $0.oldPath) }
		state[keyPath: target].append(contentsOf: newFiles)
		state[keyPath: target].sort { $0.path < $1.path }
	}

	private func removeFromUnstaged(_ files: [FileChange], state: inout State) -> Effect<Action> {
		let fileIds = Set(files.map(\.id))
		state.unstaged.files.removeAll { fileIds.contains($0.id) }
		return handleAutoSelection(state: &state, staged: state.staged.files, unstaged: state.unstaged.files)
	}

	private func handleAutoSelection(
		state: inout State,
		staged: [FileChange],
		unstaged: [FileChange]
	) -> Effect<Action> {
		guard state.lastActionedFileId != nil else {
			if let selectedFileId = state.diffViewer.fileId, let wasStaged = state.diffViewer.fileIsStaged {
				if wasStaged, let file = staged.first(where: { $0.id == selectedFileId }) {
					return .send(.selectFile(file, isStaged: true))
				}
				else if !wasStaged, let file = unstaged.first(where: { $0.id == selectedFileId }) {
					return .send(.selectFile(file, isStaged: false))
				}
				else {
					state.diffViewer.fileId = nil
					state.diffViewer.fileIsStaged = nil
					state.diffViewer.fileDiff = nil
				}
			}
			else {
				if let firstUnstaged = unstaged.first {
					return .send(.selectFile(firstUnstaged, isStaged: false))
				}
				else if let firstStaged = staged.first {
					return .send(.selectFile(firstStaged, isStaged: true))
				}
			}
			return .none
		}

		state.lastActionedFileId = nil
		let actionedIndex = state.lastActionedFileIndex
		state.lastActionedFileIndex = nil
		state.unstaged.selectedFileIds.removeAll()
		state.staged.selectedFileIds.removeAll()

		let (sourceList, targetList, isStaged) = state.wasStaging
			? (unstaged, staged, false)
			: (staged, unstaged, true)

		if let index = actionedIndex {
			if index < sourceList.count {
				return .send(.selectFile(sourceList[index], isStaged: isStaged))
			}
			else if index > 0, !sourceList.isEmpty {
				return .send(.selectFile(sourceList[sourceList.count - 1], isStaged: isStaged))
			}
		}

		if let firstTarget = targetList.first {
			return .send(.selectFile(firstTarget, isStaged: !isStaged))
		}

		state.diffViewer.fileId = nil
		state.diffViewer.fileIsStaged = nil
		state.diffViewer.fileDiff = nil
		return .none
	}
}
