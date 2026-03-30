import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Pull Button Reducer

@Reducer
public struct PullButtonReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		var isPulling = false
	}

	public enum Action: Equatable {
		case pullTapped
		case pullCompleted(result: GitPullHelper.PullResult?, error: GitError?)
	}

	@Dependency(GitClient.self)
	private var gitClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .pullTapped:
				state.isPulling = true
				return .run { [path = state.repositoryPath, gitClient] send in
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

			case .pullCompleted:
				state.isPulling = false
				return .none
			}
		}
	}
}
