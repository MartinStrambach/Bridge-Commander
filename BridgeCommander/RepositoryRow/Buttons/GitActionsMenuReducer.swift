import ComposableArchitecture
import Foundation

// MARK: - Git Actions Menu Reducer

@Reducer
struct GitActionsMenuReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isMergingMaster: Bool = false
		@Presents
		var alert: AlertState<Action.Alert>?
	}

	enum Action: Equatable {
		case mergeMasterTapped
		case mergeMasterStarted
		case mergeMasterCompleted(success: Bool, error: GitMergeMasterHelper.MergeError?)
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
				return .send(.mergeMasterStarted)

			case .mergeMasterStarted:
				return .run { [path = state.repositoryPath] send in
					do {
						try await gitService.mergeMaster(at: path)
						await send(.mergeMasterCompleted(success: true, error: nil))
					}
					catch let error as GitMergeMasterHelper.MergeError {
						await send(.mergeMasterCompleted(success: false, error: error))
					}
					catch {
						print("Unexpected error during merge: \(error)")
						await send(.mergeMasterCompleted(success: true, error: nil))
					}
				}

			case let .mergeMasterCompleted(_, error):
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
