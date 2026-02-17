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
		var unpushedCommitsCount = 0
		var fetchButton: FetchButtonReducer.State
		var pullButton: PullButtonReducer.State
		var pushButton: PushButtonReducer.State
		var mergeMasterButton: MergeMasterButtonReducer.State
		var abortMergeButton: AbortMergeButtonReducer.State
		var stashButton: StashButtonReducer.State

		init(repositoryPath: String, currentBranch: String) {
			self.repositoryPath = repositoryPath
			self.currentBranch = currentBranch
			self.fetchButton = FetchButtonReducer.State(repositoryPath: repositoryPath)
			self.pullButton = PullButtonReducer.State(repositoryPath: repositoryPath)
			self.pushButton = PushButtonReducer.State(repositoryPath: repositoryPath)
			self.mergeMasterButton = MergeMasterButtonReducer.State(repositoryPath: repositoryPath)
			self.abortMergeButton = AbortMergeButtonReducer.State(repositoryPath: repositoryPath)
			self.stashButton = StashButtonReducer.State(repositoryPath: repositoryPath)
		}
	}

	enum Action: Equatable {
		case onAppear
		case didCheckGitStatus(hasRemoteBranch: Bool, isMergeInProgress: Bool, unpushedCommitsCount: Int)
		case fetchButton(FetchButtonReducer.Action)
		case pullButton(PullButtonReducer.Action)
		case pushButton(PushButtonReducer.Action)
		case mergeMasterButton(MergeMasterButtonReducer.Action)
		case abortMergeButton(AbortMergeButtonReducer.Action)
		case stashButton(StashButtonReducer.Action)
	}

	var body: some Reducer<State, Action> {
		Scope(state: \.fetchButton, action: \.fetchButton) {
			FetchButtonReducer()
		}

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

		Scope(state: \.stashButton, action: \.stashButton) {
			StashButtonReducer()
		}

		Reduce { state, action in
			switch action {
			case .abortMergeButton(.abortMergeCompleted),
			     .fetchButton(.fetchCompleted),
			     .mergeMasterButton(.mergeMasterCompleted),
			     .onAppear,
			     .pullButton(.pullCompleted),
			     .pushButton(.pushCompleted):
				return .merge(
					.run { [path = state.repositoryPath] send in
						let hasRemote = await GitRemoteBranchDetector.hasRemoteBranch(at: path)
						let isMergeInProgress = GitMergeDetector.isGitOperationInProgress(at: path)
						let unpushedCount = await GitBranchDetector.countUnpushedCommits(at: path)
						await send(.didCheckGitStatus(hasRemoteBranch: hasRemote, isMergeInProgress: isMergeInProgress, unpushedCommitsCount: unpushedCount))
					},
					.send(.stashButton(.checkStashStatus))
				)

			case let .didCheckGitStatus(hasRemote, isMergeInProgress, unpushedCount):
				state.hasRemoteBranch = hasRemote
				state.isMergeInProgress = isMergeInProgress
				state.unpushedCommitsCount = unpushedCount
				return .none

			case .stashButton(.stashCompleted),
			     .stashButton(.stashPopCompleted):
				return .send(.stashButton(.checkStashStatus))

			default:
				return .none
			}
		}
	}
}
