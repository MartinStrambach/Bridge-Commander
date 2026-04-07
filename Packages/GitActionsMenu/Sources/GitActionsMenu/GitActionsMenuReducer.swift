import AppUI
import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Git Actions Menu Reducer

@Reducer
public struct GitActionsMenuReducer {
	@ObservableState
	public struct State: Equatable {
		public var isMergeInProgress = false
		public var currentBranch: String
		public var hasRemoteBranch = false
		public var unpushedCommitsCount = 0
		public var stashButton: StashButtonReducer.State

		let repositoryPath: String
		var fetchButton: FetchButtonReducer.State
		var pullButton: PullButtonReducer.State
		var pushButton: PushButtonReducer.State
		var mergeMasterButton: MergeMasterButtonReducer.State
		var abortMergeButton: AbortMergeButtonReducer.State
		@Presents
		var alert: ScrollableAlertReducer.State?

		fileprivate var isLoaded = false

		public init(repositoryPath: String, currentBranch: String) {
			self.repositoryPath = repositoryPath
			self.currentBranch = currentBranch
			self.fetchButton = FetchButtonReducer.State(repositoryPath: repositoryPath)
			self.pullButton = PullButtonReducer.State(repositoryPath: repositoryPath)
			self.pushButton = PushButtonReducer.State(repositoryPath: repositoryPath)
			self.mergeMasterButton = MergeMasterButtonReducer.State(repositoryPath: repositoryPath)
			self.abortMergeButton = AbortMergeButtonReducer.State(repositoryPath: repositoryPath)
			self.stashButton = StashButtonReducer.State(repositoryPath: repositoryPath, currentBranch: currentBranch)
		}
	}

	public enum Action: Equatable {
		case onAppear
		case refresh
		case didCheckGitStatus(isMergeInProgress: Bool)
		case fetchButton(FetchButtonReducer.Action)
		case pullButton(PullButtonReducer.Action)
		case pushButton(PushButtonReducer.Action)
		case mergeMasterButton(MergeMasterButtonReducer.Action)
		case abortMergeButton(AbortMergeButtonReducer.Action)
		case stashButton(StashButtonReducer.Action)
		case alert(PresentationAction<ScrollableAlertReducer.Action>)
	}

	public var body: some Reducer<State, Action> {
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
					state.alert = ScrollableAlertReducer.State(
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
					state.alert = ScrollableAlertReducer.State(title: "Fetch Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .pullButton(.pullCompleted(result, error)):
				if let error {
					state.alert = ScrollableAlertReducer.State(
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
					state.alert = ScrollableAlertReducer.State(title: "Pull Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .pushButton(.pushCompleted(result, error)):
				if let error {
					state.alert = ScrollableAlertReducer.State(
						title: "Push Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				else if let result {
					let message = result.isUpToDate
						? "Everything is already up to date with the remote branch."
						: "Successfully pushed commits to remote branch."
					state.alert = ScrollableAlertReducer.State(title: "Push Successful", message: message, isError: false)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .mergeMasterButton(.mergeMasterCompleted(result)):
				switch result {
				case let .success(mergeResult):
					let (title, message) = mergeResult.commitsMerged
						? ("Merge Successful", "Successfully merged commits from master.")
						: ("Already Up to Date", "Branch is already up to date with master. No commits were merged.")
					state.alert = ScrollableAlertReducer.State(title: title, message: message, isError: false)

				case let .failure(error):
					state.alert = ScrollableAlertReducer.State(
						title: "Merge Failed",
						message: error.localizedDescription,
						isError: true
					)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .abortMergeButton(.abortMergeCompleted(success, error)):
				if let error {
					state.alert = ScrollableAlertReducer.State(title: "Abort Merge Failed", message: error, isError: true)
				}
				else if success {
					state.alert = ScrollableAlertReducer.State(
						title: "Merge Aborted",
						message: "The merge has been successfully aborted.",
						isError: false
					)
				}
				return checkStatusEffect(path: state.repositoryPath)

			case let .stashButton(.stashCompleted(success, error)):
				if let error {
					state.alert = ScrollableAlertReducer.State(title: "Stash Failed", message: error, isError: true)
				}
				else if success {
					state.alert = ScrollableAlertReducer.State(
						title: "Stash Successful",
						message: "Changes have been stashed successfully.",
						isError: false
					)
				}
				return .send(.stashButton(.checkStashStatus))

			case let .stashButton(.stashPopCompleted(success, error)):
				if let error {
					state.alert = ScrollableAlertReducer.State(title: "Stash Pop Failed", message: error, isError: true)
				}
				else if success {
					state.alert = ScrollableAlertReducer.State(
						title: "Stash Pop Successful",
						message: "Stashed changes have been restored successfully.",
						isError: false
					)
				}
				return .send(.stashButton(.checkStashStatus))

			case .onAppear:
				guard !state.isLoaded else {
					return .none
				}

				state.isLoaded = true
				return checkStatusEffect(path: state.repositoryPath)

			case .refresh:
				return checkStatusEffect(path: state.repositoryPath)

			case let .didCheckGitStatus(isMergeInProgress):
				state.isMergeInProgress = isMergeInProgress
				return .none

			default:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert) {
			ScrollableAlertReducer()
		}
	}

	public init() {}

	private func checkStatusEffect(path: String) -> EffectOf<GitActionsMenuReducer> {
		.merge(
			.run { send in
				let isMergeInProgress = GitMergeDetector.isGitOperationInProgress(at: path)
				await send(.didCheckGitStatus(isMergeInProgress: isMergeInProgress))
			},
			.send(.stashButton(.checkStashStatus))
		)
	}
}
