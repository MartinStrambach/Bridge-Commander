import ComposableArchitecture
import Foundation

// MARK: - Merge Master Button Reducer

@Reducer
struct MergeMasterButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isMergingMaster = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case mergeMasterTapped
		case mergeMasterCompleted(error: GitMergeMasterHelper.MergeError?)
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
						try await gitService.mergeMaster(at: path)
						await send(.mergeMasterCompleted(error: nil))
					}
					catch let error as GitMergeMasterHelper.MergeError {
						await send(.mergeMasterCompleted(error: error))
					}
					catch {
						print("Unexpected error during merge: \(error)")
						await send(.mergeMasterCompleted(error: nil))
					}
				}

			case let .mergeMasterCompleted(error):
				state.isMergingMaster = false
				if let error {
					let message =
						switch error {
						case let .fetchFailed(msg):
							"Fetch failed: \(msg)"
						case let .mergeFailed(msg):
							"Merge failed: \(msg)"
						}
					state.alert = AlertState {
						TextState("Git Operation Failed")
					} actions: {
						ButtonState(role: .cancel) {
							TextState("OK")
						}
					} message: {
						TextState(message)
					}
				}
				return .none

			case .alert:
				return .none
			}
		}
		.ifLet(\.$alert, action: \.alert)
	}
}
