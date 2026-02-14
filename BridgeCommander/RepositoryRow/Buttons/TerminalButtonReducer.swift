import ComposableArchitecture
import Foundation

// MARK: - Terminal Button Reducer

@Reducer
struct TerminalButtonReducer {
	@ObservableState
	struct State: Equatable {
		let repositoryPath: String

		@Shared(.terminalOpeningBehavior)
		var terminalOpeningBehavior = TerminalOpeningBehavior.newTab
	}

	enum Action: Equatable {
		case openTerminalButtonTapped
	}

	var body: some Reducer<State, Action> {
		Reduce { state, action in
			switch action {
			case .openTerminalButtonTapped:
				.run { [path = state.repositoryPath, behavior = state.terminalOpeningBehavior] _ in
					await TerminalLauncher.openTerminal(at: path, behavior: behavior)
				}
			}
		}
	}
}
