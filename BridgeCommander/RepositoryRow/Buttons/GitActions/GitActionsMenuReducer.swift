import ComposableArchitecture
import Foundation

// MARK: - Git Actions Menu Reducer

@Reducer
struct GitActionsMenuReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var currentBranch: String
		var hasRemoteBranch = false
		var isMergeInProgress = false
		var pullButton: PullButtonReducer.State
		var pushButton: PushButtonReducer.State
		var mergeMasterButton: MergeMasterButtonReducer.State
		var abortMergeButton: AbortMergeButtonReducer.State

		init(repositoryPath: String, currentBranch: String) {
			self.repositoryPath = repositoryPath
			self.currentBranch = currentBranch
			self.pullButton = PullButtonReducer.State(repositoryPath: repositoryPath)
			self.pushButton = PushButtonReducer.State(repositoryPath: repositoryPath)
			self.mergeMasterButton = MergeMasterButtonReducer.State(repositoryPath: repositoryPath)
			self.abortMergeButton = AbortMergeButtonReducer.State(repositoryPath: repositoryPath)
		}
	}

	enum Action: Equatable {
		case onAppear
		case didCheckGitStatus(hasRemoteBranch: Bool, isMergeInProgress: Bool)
		case pullButton(PullButtonReducer.Action)
		case pushButton(PushButtonReducer.Action)
		case mergeMasterButton(MergeMasterButtonReducer.Action)
		case abortMergeButton(AbortMergeButtonReducer.Action)
	}

	var body: some Reducer<State, Action> {
		Scope(state: \.pullButton, action: \.pullButton) {
			PullButtonReducer()
		}

		Scope(state: \.pushButton, action: \.pushButton) {
			PushButtonReducer()
		}

		Scope(state: \.mergeMasterButton, action: \.mergeMasterButton) {
			MergeMasterButtonReducer()
		}

		Scope(state: \.abortMergeButton, action: \.abortMergeButton) {
			AbortMergeButtonReducer()
		}

		Reduce { state, action in
			switch action {
			case .onAppear,
			     .pullButton(.pullCompleted),
			     .pushButton(.pushCompleted),
			     .mergeMasterButton(.mergeMasterCompleted),
			     .abortMergeButton(.abortMergeCompleted):
				return .run { [path = state.repositoryPath] send in
					let hasRemote = await GitRemoteBranchDetector.hasRemoteBranch(at: path)
					let isMergeInProgress = GitMergeDetector.isGitOperationInProgress(at: path)
					await send(.didCheckGitStatus(hasRemoteBranch: hasRemote, isMergeInProgress: isMergeInProgress))
				}

			case let .didCheckGitStatus(hasRemote, isMergeInProgress):
				state.hasRemoteBranch = hasRemote
				state.isMergeInProgress = isMergeInProgress
				return .none

			default:
				return .none
			}
		}
	}
}
