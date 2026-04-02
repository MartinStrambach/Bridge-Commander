import AppUI
import ComposableArchitecture
import Foundation
import GitCore
import Settings
import ToolsIntegration

typealias FileChange = GitCore.FileChange
typealias FileChangeStatus = GitCore.FileChangeStatus

struct PendingSelection: Equatable {
	let sourceIndex: Int
	let sourceWasUnstaged: Bool
}

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
		var unpushedCommitsCount: Int = 0
		var isPushing: Bool = false
		var isLoadingChanges: Bool = false
		var pendingSelection: PendingSelection?

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

	enum Action {
		case alert(PresentationAction<GitAlertReducer.Action>)
		case cancelButtonTapped
		case commitButtonTapped
		case commitSheet(PresentationAction<CommitReducer.Action>)
		case pushButtonTapped
		case pushCompleted(result: GitPushHelper.PushResult?, error: GitError?)
		case deleteFilesCompleted([FileChange])
		case discardFilesCompleted([FileChange])
		case diffViewer(FileDiffViewer.Action)
		case loadChanges
		case loadChangesResponse(GitFileChanges)
		case mergeStatus(MergeStatus.Action)
		case openTerminalButtonTapped
		case selectFile(FileChange, isStaged: Bool)
		case staged(FileChangeList.Action)
		case stageFilesCompleted
		case unstaged(FileChangeList.Action)
		case unstageFilesCompleted
		case operationCompleted(Result<Void, Error>)
	}

	private nonisolated enum CancellableId: Hashable {
		case loadChanges
	}

	@Dependency(GitStagingClient.self)
	private var gitStagingClient

	@Dependency(GitClient.self)
	private var gitClient

	@Dependency(\.dismiss)
	private var dismiss

	@Shared(.terminalApp)
	private var terminalApp = TerminalApp.systemTerminal

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
				state.isLoadingChanges = true
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
				state.isLoadingChanges = false
				state.staged.isLoading = false
				state.staged.files = changes.staged
				state.unstaged.isLoading = false
				state.unstaged.files = changes.unstaged
				state.unpushedCommitsCount = changes.unpushedCount
				let pendingSelection = state.pendingSelection
				state.pendingSelection = nil
				return handleAutoSelection(
					state: &state,
					staged: changes.staged,
					unstaged: changes.unstaged,
					pendingSelection: pendingSelection
				)

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

				let stagedFileIds = Set(files.map(\.id))
				let lastIndex = state.unstaged.files.lastIndex(where: { stagedFileIds.contains($0.id) }) ?? 0
				state.pendingSelection = PendingSelection(sourceIndex: lastIndex, sourceWasUnstaged: true)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.stageFiles(path, paths)
						await send(.stageFilesCompleted)
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case .stageFilesCompleted:
				return .run { [path = state.repositoryPath] send in
					let changes = await gitStagingClient.fetchFileChanges(path)
					await send(.loadChangesResponse(changes))
				}

			case let .staged(.delegate(.toggleAll(files))):
				guard !files.isEmpty else {
					return .none
				}

				let unstagingFileIds = Set(files.map(\.id))
				let lastIndex = state.staged.files.lastIndex(where: { unstagingFileIds.contains($0.id) }) ?? 0
				state.pendingSelection = PendingSelection(sourceIndex: lastIndex, sourceWasUnstaged: false)
				return .run { [path = state.repositoryPath, paths = files.map(\.path)] send in
					do {
						try await gitStagingClient.unstageFiles(path, paths)
						await send(.unstageFilesCompleted)
					}
					catch { await send(.operationCompleted(.failure(error))) }
				}

			case .unstageFilesCompleted:
				return .run { [path = state.repositoryPath] send in
					let changes = await gitStagingClient.fetchFileChanges(path)
					await send(.loadChangesResponse(changes))
				}

			case let .unstaged(.delegate(.discardChanges(files))):
				guard !files.isEmpty else {
					return .none
				}

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
				let index = list.firstIndex(where: { $0.id == fileId }) ?? 0
				if isStaged {
					state.staged.files.removeAll { $0.id == fileId }
				}
				else {
					state.unstaged.files.removeAll { $0.id == fileId }
				}
				let pending = PendingSelection(sourceIndex: index, sourceWasUnstaged: !isStaged)
				return handleAutoSelection(
					state: &state,
					staged: state.staged.files,
					unstaged: state.unstaged.files,
					pendingSelection: pending
				)

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
				let title: String
				if let gitError = error as? GitError, case .mergeFailed = gitError {
					title = "Finish Merge Failed"
				} else if let gitError = error as? GitError, case .abortMergeFailed = gitError {
					title = "Finish Merge Failed"
				} else {
					title = "Operation Failed"
				}
				state.alert = GitAlertReducer.State(
					title: title,
					message: error.localizedDescription,
					isError: true
				)
				return .none

			case .pushButtonTapped:
				state.isPushing = true
				return .run { [path = state.repositoryPath] send in
					do {
						let result = try await GitPushHelper.push(at: path)
						await send(.pushCompleted(result: result, error: nil))
					}
					catch let error as GitError {
						await send(.pushCompleted(result: nil, error: error))
					}
					catch {
						await send(.pushCompleted(result: nil, error: nil))
					}
				}

			case let .pushCompleted(result: _, error: error):
				state.isPushing = false
				if let error {
					state.alert = GitAlertReducer.State(
						title: "Push Failed",
						message: error.localizedDescription,
						isError: true
					)
					return .none
				}
				return .send(.loadChanges)

			case .commitButtonTapped:
				state.commitSheet = CommitReducer.State(repositoryPath: state.repositoryPath)
				return .none

			case .commitSheet(.presented(.delegate(.commitSucceeded))):
				return .send(.operationCompleted(.success(())))

			case .cancelButtonTapped:
				return .run { _ in await dismiss() }

			case .openTerminalButtonTapped:
				return .run { [path = state.repositoryPath, app = terminalApp, behavior = terminalOpeningBehavior] _ in
					await TerminalLauncher.openTerminal(at: path, app: app, behavior: behavior)
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

	private func removeFromUnstaged(_ files: [FileChange], state: inout State) -> EffectOf<RepositoryDetail> {
		let fileIds = Set(files.map(\.id))
		let lastIndex = state.unstaged.files.lastIndex(where: { fileIds.contains($0.id) }) ?? 0
		state.unstaged.files.removeAll { fileIds.contains($0.id) }
		let pending = PendingSelection(sourceIndex: lastIndex, sourceWasUnstaged: true)
		return handleAutoSelection(
			state: &state,
			staged: state.staged.files,
			unstaged: state.unstaged.files,
			pendingSelection: pending
		)
	}

	private func handleAutoSelection(
		state: inout State,
		staged: [FileChange],
		unstaged: [FileChange],
		pendingSelection: PendingSelection? = nil
	) -> EffectOf<RepositoryDetail> {
		if let pending = pendingSelection {
			let sourceList = pending.sourceWasUnstaged ? unstaged : staged
			let targetList = pending.sourceWasUnstaged ? staged : unstaged
			let sourceIsStaged = !pending.sourceWasUnstaged
			if pending.sourceIndex < sourceList.count {
				return .send(.selectFile(sourceList[pending.sourceIndex], isStaged: sourceIsStaged))
			}
			else if let last = sourceList.last {
				return .send(.selectFile(last, isStaged: sourceIsStaged))
			}
			else if let first = targetList.first {
				return .send(.selectFile(first, isStaged: !sourceIsStaged))
			}
		}
		else if let selectedFileId = state.diffViewer.fileId, let wasStaged = state.diffViewer.fileIsStaged {
			if wasStaged, let file = staged.first(where: { $0.id == selectedFileId }) {
				return .send(.selectFile(file, isStaged: true))
			}
			else if !wasStaged, let file = unstaged.first(where: { $0.id == selectedFileId }) {
				return .send(.selectFile(file, isStaged: false))
			}
			else if let firstUnstaged = unstaged.first {
				return .send(.selectFile(firstUnstaged, isStaged: false))
			}
			else if let firstStaged = staged.first {
				return .send(.selectFile(firstStaged, isStaged: true))
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
		state.diffViewer.fileId = nil
		state.diffViewer.fileIsStaged = nil
		state.diffViewer.fileDiff = nil
		return .none
	}
}
