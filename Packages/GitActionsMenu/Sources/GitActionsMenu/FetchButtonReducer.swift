import ComposableArchitecture
import Foundation
import GitCore

// MARK: - Fetch Button Reducer

@Reducer
public struct FetchButtonReducer {
	@ObservableState
	public struct State: Equatable {
		let repositoryPath: String
		var isFetching = false
	}

	public enum Action: Equatable {
		case fetchTapped
		case fetchCompleted(result: GitFetchHelper.FetchResult?, error: GitError?)
	}

	@Dependency(GitClient.self)
	private var gitClient

	public var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .fetchTapped:
				state.isFetching = true
				return .run { [path = state.repositoryPath, gitClient] send in
					do {
						let result = try await gitClient.fetch(at: path)
						await send(.fetchCompleted(result: result, error: nil))
					}
					catch let error as GitError {
						await send(.fetchCompleted(result: nil, error: error))
					}
					catch {
						print("Unexpected error during fetch: \(error)")
						await send(.fetchCompleted(result: nil, error: nil))
					}
				}

			case .fetchCompleted:
				state.isFetching = false
				return .none
			}
		}
	}
}
