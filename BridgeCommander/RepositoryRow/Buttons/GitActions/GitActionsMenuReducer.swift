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
		var mergeMasterButton: MergeMasterButtonReducer.State

		init(repositoryPath: String, currentBranch: String) {
			self.repositoryPath = repositoryPath
			self.currentBranch = currentBranch
			self.pullButton = PullButtonReducer.State(repositoryPath: repositoryPath)
			self.mergeMasterButton = MergeMasterButtonReducer.State(repositoryPath: repositoryPath)
		}
	}

	enum Action: Equatable {
		case onAppear
		case didCheckRemoteBranch(Bool)
		case pullButton(PullButtonReducer.Action)
		case mergeMasterButton(MergeMasterButtonReducer.Action)
	}

	var body: some Reducer<State, Action> {
		Scope(state: \.pullButton, action: \.pullButton) {
			PullButtonReducer()
		}

		Scope(state: \.mergeMasterButton, action: \.mergeMasterButton) {
			MergeMasterButtonReducer()
		}

		Reduce { state, action in
			switch action {
			case .onAppear,
			     .pullButton(.pullCompleted):
				return .run { [path = state.repositoryPath] send in
					let hasRemote = await GitRemoteBranchDetector.hasRemoteBranch(at: path)
					await send(.didCheckRemoteBranch(hasRemote))
				}

			case let .didCheckRemoteBranch(hasRemote):
				state.hasRemoteBranch = hasRemote
				return .none

			default:
				return .none
			}
		}
	}
}
