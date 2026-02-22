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
		@Presents
		var alert: GitAlertReducer.State?

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
		case alert(PresentationAction<GitAlertReducer.Action>)
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
			case let .fetchButton(.fetchCompleted(result, error)):
				if let error {
					state.alert = GitAlertReducer.State(
						title: "Fetch Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				else if let result {
					let message =
						if result.isAlreadyUpToDate {
							"Already up to date. No new remote changes found."
						}
						else if result.fetchedBranches > 0 {
							"Successfully fetched updates for \(result.fetchedBranches) branch\(result.fetchedBranches == 1 ? "" : "es")."
						}
						else {
							"Fetch completed successfully."
						}
					state.alert = GitAlertReducer.State(title: "Fetch Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .pullButton(.pullCompleted(result, error)):
				if let error {
					state.alert = GitAlertReducer.State(
						title: "Pull Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				else if let result {
					let message =
						if result.isAlreadyUpToDate {
							"Your branch is already up to date with the remote branch."
						}
						else if result.commitCount > 0 {
							"Successfully pulled \(result.commitCount) commit\(result.commitCount == 1 ? "" : "s") from remote branch."
						}
						else {
							"Pull completed successfully."
						}
					state.alert = GitAlertReducer.State(title: "Pull Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .pushButton(.pushCompleted(result, error)):
				if let error {
					state.alert = GitAlertReducer.State(
						title: "Push Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				else if let result {
					let message = result.isUpToDate
						? "Everything is already up to date with the remote branch."
						: "Successfully pushed commits to remote branch."
					state.alert = GitAlertReducer.State(title: "Push Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .mergeMasterButton(.mergeMasterCompleted(result)):
				switch result {
				case let .success(mergeResult):
					let (title, message) = mergeResult.commitsMerged
						? ("Merge Successful", "Successfully merged commits from master.")
						: ("Already Up to Date", "Branch is already up to date with master. No commits were merged.")
					state.alert = GitAlertReducer.State(title: title, message: message, isError: false)

				case let .failure(error):
					state.alert = GitAlertReducer.State(
						title: "Merge Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .abortMergeButton(.abortMergeCompleted(success, error)):
				if let error {
					state.alert = GitAlertReducer.State(title: "Abort Merge Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlertReducer.State(
						title: "Merge Aborted",
						message: "The merge has been successfully aborted.",
						isError: false
					)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .stashButton(.stashCompleted(success, error)):
				if let error {
					state.alert = GitAlertReducer.State(title: "Stash Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlertReducer.State(
						title: "Stash Successful",
						message: "Changes have been stashed successfully.",
						isError: false
					)
				}
				return .send(.stashButton(.checkStashStatus))

			case let .stashButton(.stashPopCompleted(success, error)):
				if let error {
					state.alert = GitAlertReducer.State(title: "Stash Pop Failed", message: error, isError: true)
				}
				else if success {
					state.alert = GitAlertReducer.State(
						title: "Stash Pop Successful",
						message: "Stashed changes have been restored successfully.",
						isError: false
					)
				}
				return .send(.stashButton(.checkStashStatus))

			case .onAppear:
				return checkStatusEffect(path: state.repositoryPath)

			case let .didCheckGitStatus(hasRemote, isMergeInProgress, unpushedCount):
				state.hasRemoteBranch = hasRemote
				state.isMergeInProgress = isMergeInProgress
				state.unpushedCommitsCount = unpushedCount
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			GitAlertReducer()
		}
	}

	private func checkStatusEffect(path: String) -> Effect<Action> {
		.merge(
			.run { send in
				let hasRemote = await GitRemoteBranchDetector.hasRemoteBranch(at: path)
				let isMergeInProgress = GitMergeDetector.isGitOperationInProgress(at: path)
				let unpushedCount = await GitBranchDetector.countUnpushedCommits(at: path)
				await send(.didCheckGitStatus(
					hasRemoteBranch: hasRemote,
					isMergeInProgress: isMergeInProgress,
					unpushedCommitsCount: unpushedCount
				))
			},
			.send(.stashButton(.checkStashStatus))
		)
	}
}
