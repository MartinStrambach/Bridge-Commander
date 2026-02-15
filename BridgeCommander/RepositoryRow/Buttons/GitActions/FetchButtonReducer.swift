import ComposableArchitecture
import Foundation

// MARK: - Fetch Button Reducer

@Reducer
struct FetchButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isFetching = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case fetchTapped
		case fetchCompleted(result: GitFetchHelper.FetchResult?, error: GitError?)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
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
					state.alert = .okAlert(title: "Git Operation Failed", message: error.localizedDescription)
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

					state.alert = .okAlert(title: "Fetch Successful", message: message)
				}
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
