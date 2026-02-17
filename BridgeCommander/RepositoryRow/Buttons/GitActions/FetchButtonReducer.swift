import ComposableArchitecture
import Foundation

// MARK: - Fetch Button Reducer

@Reducer
struct FetchButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isFetching = false
		var alert: GitAlert?
	}

	enum Action: Equatable {
		case fetchTapped
		case fetchCompleted(result: GitFetchHelper.FetchResult?, error: GitError?)
	}

	@Dependency(GitClient.self)
	private var gitClient

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .fetchTapped:
				state.isFetching = true
				return .run { [path = state.repositoryPath] send in
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

			case let .fetchCompleted(result, error):
				state.isFetching = false
				if let error {
					state.alert = GitAlert(title: "Fetch Failed", message: error.localizedDescription, isError: true)
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
					state.alert = GitAlert(title: "Fetch Successful", message: message, isError: false)
				}
				return .none

			}
		}
	}
}
