import ComposableArchitecture
import Foundation

// MARK: - Merge Master Button Reducer

@Reducer
struct MergeMasterButtonReducer {
	@ObservableState
	struct State: Equatable {
		var isMergingMaster = false
		var alert: GitAlert?

		fileprivate let repositoryPath: String

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}
	}

	enum Action: Equatable {
		case mergeMasterTapped
		case mergeMasterCompleted(result: Result<GitMergeHelper.MergeResult, GitError>)
	}

	@Dependency(GitClient.self)
	private var gitClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .mergeMasterTapped:
				state.isMergingMaster = true
				return .run { [path = state.repositoryPath] send in
					do {
						let mergeResult = try await gitClient.mergeMaster(at: path)
						await send(.mergeMasterCompleted(result: .success(mergeResult)))
					}
					catch let error as GitError {
						await send(.mergeMasterCompleted(result: .failure(error)))
					}
					catch {
						print("Unexpected error during merge: \(error)")
						await send(.mergeMasterCompleted(result: .failure(.mergeFailed(error.localizedDescription))))
					}
				}

			case let .mergeMasterCompleted(result):
				state.isMergingMaster = false
				switch result {
				case let .success(mergeResult):
					let (title, message) = mergeResult.commitsMerged
						? ("Merge Successful", "Successfully merged commits from master.")
						: ("Already Up to Date", "Branch is already up to date with master. No commits were merged.")
					state.alert = GitAlert(title: title, message: message, isError: false)

				case let .failure(error):
					state.alert = GitAlert(title: "Merge Failed", message: error.localizedDescription, isError: true)
				}
				return .none

			}
		}
	}
}
