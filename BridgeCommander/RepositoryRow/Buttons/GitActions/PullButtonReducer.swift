import ComposableArchitecture
import Foundation

// MARK: - Pull Button Reducer

@Reducer
struct PullButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isPulling = false
		var alert: GitAlert?
	}

	enum Action: Equatable {
		case pullTapped
		case pullCompleted(result: GitPullHelper.PullResult?, error: GitError?)
	}

	@Dependency(GitClient.self)
	private var gitClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .pullTapped:
				state.isPulling = true
				return .run { [path = state.repositoryPath] send in
					do {
						let result = try await gitClient.pull(at: path)
						await send(.pullCompleted(result: result, error: nil))
					}
					catch let error as GitError {
						await send(.pullCompleted(result: nil, error: error))
					}
					catch {
						print("Unexpected error during pull: \(error)")
						await send(.pullCompleted(result: nil, error: nil))
					}
				}

			case let .pullCompleted(result, error):
				state.isPulling = false
				if let error {
					state.alert = GitAlert(title: "Pull Failed", message: error.localizedDescription, isError: true)
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
					state.alert = GitAlert(title: "Pull Successful", message: message, isError: false)
				}
				return .none

			}
		}
	}
}
