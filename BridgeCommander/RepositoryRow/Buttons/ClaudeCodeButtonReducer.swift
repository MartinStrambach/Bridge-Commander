import ComposableArchitecture
import Foundation

@Reducer
struct ClaudeCodeButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String
		var isLaunching: Bool = false
		var errorMessage: String?
	}

	enum Action: Equatable {
		case launchClaudeCodeButtonTapped
		case didLaunchClaudeCode
		case launchFailed(String)
		case dismissError
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .launchClaudeCodeButtonTapped:
				state.isLaunching = true
				return .run { [path = state.repositoryPath] send in
					do {
						try ClaudeCodeLauncher.runClaudeCode(at: path)
						await send(.didLaunchClaudeCode)
					}
					catch {
						await send(.launchFailed(error.localizedDescription))
					}
				}

			case .didLaunchClaudeCode:
				state.isLaunching = false
				return .none

			case let .launchFailed(errorMessage):
				state.isLaunching = false
				state.errorMessage = errorMessage
				return .none

			case .dismissError:
				state.errorMessage = nil
				return .none
			}
		}
	}
}
