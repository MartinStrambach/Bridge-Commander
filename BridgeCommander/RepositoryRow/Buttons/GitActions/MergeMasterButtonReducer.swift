import ComposableArchitecture
import Foundation

// MARK: - Merge Master Button Reducer

@Reducer
struct MergeMasterButtonReducer {
	@ObservableState
	struct State: Equatable {
		var isMergingMaster = false
		@Presents
		var alert: AlertState<Action.Alert>?

		fileprivate let repositoryPath: String

		init(repositoryPath: String) {
			self.repositoryPath = repositoryPath
		}
	}

	enum Action: Equatable {
		case mergeMasterTapped
		case mergeMasterCompleted(result: Result<GitMergeMasterHelper.MergeResult, GitMergeMasterHelper.MergeError>)
		case alert(PresentationAction<Alert>)

		enum Alert: Equatable {}
	}

	@Dependency(\.gitService)
	private var gitService

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .mergeMasterTapped:
				state.isMergingMaster = true
				return .run { [path = state.repositoryPath] send in
					do {
						let mergeResult = try await gitService.mergeMaster(at: path)
						await send(.mergeMasterCompleted(result: .success(mergeResult)))
					}
					catch let error as GitMergeMasterHelper.MergeError {
						await send(.mergeMasterCompleted(result: .failure(error)))
					}
					catch {
						print("Unexpected error during merge: \(error)")
						await send(.mergeMasterCompleted(result: .failure(.mergeFailed(error.localizedDescription))))
					}
				}

			case let .mergeMasterCompleted(result):
				state.isMergingMaster = false
				let (title, message) =
					switch result {
					case let .success(mergeResult):
						mergeResult.commitsMerged
							? ("Merge Successful", "Successfully merged commits from master.")
							: (
								"Already Up to Date",
								"Branch is already up to date with master. No commits were merged."
							)

					case let .failure(error):
						switch error {
						case let .fetchFailed(msg):
							("Git Operation Failed", "Fetch failed: \(msg)")

						case let .mergeFailed(msg):
							("Git Operation Failed", "Merge failed: \(msg)")
						}
					}

				state.alert = AlertState {
					TextState(title)
				} actions: {
					ButtonState(role: .cancel) {
						TextState("OK")
					}
				} message: {
					TextState(message)
				}
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
